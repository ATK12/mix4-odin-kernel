// SPDX-License-Identifier: GPL-2.0-only
/*
 * odin_mode - Xiaomi MIX4 (odin) full in-kernel power modes
 *   mode 0 = balanced (default), 1 = eco, 2 = perf
 * Writing mode applies, inside the kernel:
 *   - per-cluster CPU max freq (freq_qos)   eco: 1.2/1.6/1.8GHz
 *   - GPU max freq (kgsl thermal pwrlevel)  eco: 540MHz
 *   - thermal cdev ignore policy (see odin_thermal_drop)
 * All tunables are exposed under /sys/kernel/odin_mode/ so a KSU module
 * (or any root shell) can override them without recompiling.
 */
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/stat.h>
#include <linux/mutex.h>
#include <linux/cpufreq.h>
#include <linux/pm_qos.h>

#define ODIN_MODE_BALANCED	0
#define ODIN_MODE_ECO		1
#define ODIN_MODE_PERF		2

int odin_mode = ODIN_MODE_BALANCED;
EXPORT_SYMBOL_GPL(odin_mode);

/* ---------------- tunables (module/user overridable) ---------------- */
static unsigned int eco_cpu_silver = 1200000;	/* policy0 cluster */
static unsigned int eco_cpu_gold   = 1600000;	/* policy4 cluster */
static unsigned int eco_cpu_prime  = 1800000;	/* policy7 cluster */
static unsigned int eco_gpu_max    = 540000000;
/* thermal cdev overrides: -1 auto (per mode), 0 = allow caps, 1 = ignore */
static int ovr_cpu = -1, ovr_gpu = -1, ovr_iso = -1;

static DEFINE_MUTEX(odin_lock);
static struct freq_qos_request cpu_max_req[3];
static const int cluster_lead_cpu[3] = { 0, 4, 7 };

/*
 * kind: 0 = cpufreq cdev, 1 = devfreq (gpu) cdev, 2 = cpu-isolate cdev
 * state == 0 (release) is always allowed so stale caps can be cleared.
 */
bool odin_thermal_drop(int kind, unsigned long state)
{
	if (state == 0)
		return false;
	switch (kind) {
	case 0: /* cpufreq cooling: allowed in both modes (thermal engine active) */
		return ovr_cpu >= 0 ? !!ovr_cpu : false;
	case 1: /* gpu devfreq cooling: balanced ignores caps (legacy 608 unlock),
	         * eco lets the thermal engine cap the gpu */
		return ovr_gpu >= 0 ? !!ovr_gpu : odin_mode != ODIN_MODE_ECO;
	case 2: /* cpu isolate: allowed in both modes */
		return ovr_iso >= 0 ? !!ovr_iso : false;
	}
	return false;
}
EXPORT_SYMBOL_GPL(odin_thermal_drop);



/* cdev drivers register a reset hook; invoked on mode/override change so
 * stale thermal caps never linger across a switch. */
typedef void (*odin_reset_fn)(void);
static odin_reset_fn odin_resets[8];
static int odin_n_resets;

void odin_register_reset(odin_reset_fn fn)
{
	if (odin_n_resets < ARRAY_SIZE(odin_resets))
		odin_resets[odin_n_resets++] = fn;
}
EXPORT_SYMBOL_GPL(odin_register_reset);

static void odin_reset_all(void)
{
	int i;

	for (i = 0; i < odin_n_resets; i++)
		odin_resets[i]();
}

/* exported clamp hook implemented in kgsl_pwrctrl.c */
extern int kgsl_odin_clamp_max(unsigned int freq_hz);

static void odin_apply_cpu(int mode)
{
	int i;

	for (i = 0; i < 3; i++) {
		struct cpufreq_policy *policy;
		unsigned int limit;

		policy = cpufreq_cpu_get(cluster_lead_cpu[i]);
		if (!policy)
			continue;

		if (!freq_qos_request_active(&cpu_max_req[i]))
			freq_qos_add_request(&policy->constraints,
					     &cpu_max_req[i], FREQ_QOS_MAX,
					     FREQ_QOS_MAX_DEFAULT_VALUE);

		if (mode == ODIN_MODE_ECO) {
			switch (i) {
			case 0: limit = eco_cpu_silver; break;
			case 1: limit = eco_cpu_gold; break;
			default: limit = eco_cpu_prime; break;
			}
		} else {
			limit = policy->cpuinfo.max_freq;
		}
		freq_qos_update_request(&cpu_max_req[i], limit);
		cpufreq_cpu_put(policy);
	}
}

static void odin_apply_gpu(int mode)
{
	if (mode == ODIN_MODE_ECO)
		kgsl_odin_clamp_max(eco_gpu_max);
	else
		kgsl_odin_clamp_max(840000000);
}

static void odin_apply_locked(void)
{
	odin_apply_cpu(odin_mode);
	odin_apply_gpu(odin_mode);
}

/* ---------------- sysfs ---------------- */
static ssize_t mode_show(struct kobject *kobj, struct kobj_attribute *attr,
			 char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", odin_mode);
}

static ssize_t mode_store(struct kobject *kobj, struct kobj_attribute *attr,
			  const char *buf, size_t count)
{
	int val;

	if (kstrtoint(buf, 0, &val))
		return -EINVAL;
	if (val < 0 || val > 1)
		return -EINVAL;

	mutex_lock(&odin_lock);
	odin_mode = val;
	odin_reset_all();
	odin_apply_locked();
	mutex_unlock(&odin_lock);
	return count;
}

static struct kobj_attribute mode_attr = __ATTR_RW(mode);

#define ODIN_UINT_ATTR(_name, _var, _min, _max)			\
static ssize_t _name##_show(struct kobject *kobj,			\
			    struct kobj_attribute *attr, char *buf)	\
{									\
	return scnprintf(buf, PAGE_SIZE, "%u\n", _var);		\
}									\
static ssize_t _name##_store(struct kobject *kobj,			\
			     struct kobj_attribute *attr,			\
			     const char *buf, size_t count)		\
{									\
	unsigned int val;						\
									\
	if (kstrtouint(buf, 0, &val))					\
		return -EINVAL;						\
	if (val < _min || val > _max)					\
		return -EINVAL;						\
	mutex_lock(&odin_lock);						\
	_var = val;							\
	odin_apply_locked();						\
	mutex_unlock(&odin_lock);					\
	return count;							\
}									\
static struct kobj_attribute _name##_attr = __ATTR_RW(_name)

ODIN_UINT_ATTR(eco_cpu_silver, eco_cpu_silver, 300000, 3000000);
ODIN_UINT_ATTR(eco_cpu_gold, eco_cpu_gold, 300000, 3200000);
ODIN_UINT_ATTR(eco_cpu_prime, eco_cpu_prime, 300000, 3200000);
ODIN_UINT_ATTR(eco_gpu_max, eco_gpu_max, 100000000, 840000000);

#define ODIN_OVR_ATTR(_name, _var)					\
static ssize_t _name##_show(struct kobject *kobj,			\
			    struct kobj_attribute *attr, char *buf)	\
{									\
	return scnprintf(buf, PAGE_SIZE, "%d\n", _var);		\
}									\
static ssize_t _name##_store(struct kobject *kobj,			\
			     struct kobj_attribute *attr,			\
			     const char *buf, size_t count)		\
{									\
	int val;							\
									\
	if (kstrtoint(buf, 0, &val))					\
		return -EINVAL;						\
	if (val < -1 || val > 1)					\
		return -EINVAL;						\
	_var = val;							\
	return count;							\
}									\
static struct kobj_attribute _name##_attr = __ATTR_RW(_name)

ODIN_OVR_ATTR(thermal_cpu_override, ovr_cpu);
ODIN_OVR_ATTR(thermal_gpu_override, ovr_gpu);
ODIN_OVR_ATTR(thermal_isolate_override, ovr_iso);

static struct attribute *odin_mode_attrs[] = {
	&mode_attr.attr,
	&eco_cpu_silver_attr.attr,
	&eco_cpu_gold_attr.attr,
	&eco_cpu_prime_attr.attr,
	&eco_gpu_max_attr.attr,
	&thermal_cpu_override_attr.attr,
	&thermal_gpu_override_attr.attr,
	&thermal_isolate_override_attr.attr,
	NULL,
};

static struct attribute_group odin_mode_group = {
	.attrs = odin_mode_attrs,
};

static struct kobject *odin_mode_kobj;

static int __init odin_mode_init(void)
{
	int ret;

	odin_mode_kobj = kobject_create_and_add("odin_mode", kernel_kobj);
	if (!odin_mode_kobj)
		return -ENOMEM;

	ret = sysfs_create_group(odin_mode_kobj, &odin_mode_group);
	if (ret) {
		kobject_put(odin_mode_kobj);
		return ret;
	}

	mutex_lock(&odin_lock);
	odin_apply_locked();
	mutex_unlock(&odin_lock);
	return 0;
}
late_initcall(odin_mode_init);

MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("odin in-kernel power modes with module-tunable params");
