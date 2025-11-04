#ifndef _LINUX_SCHED_PELT_H
#define _LINUX_SCHED_PELT_H

#ifdef __cplusplus
extern "C" {
#endif

/* Per Entity Load Tracking (PELT) control functions */
int get_pelt_halflife(void);
int set_pelt_halflife(int num);

#ifdef __cplusplus
}
#endif

#endif /* _LINUX_SCHED_PELT_H */