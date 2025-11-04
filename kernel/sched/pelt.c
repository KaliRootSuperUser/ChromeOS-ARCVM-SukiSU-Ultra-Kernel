#include <linux/sched/pelt.h>
#include <linux/sched.h>
#include <linux/ktime.h>

/* PELT halflife configuration */
int get_pelt_halflife(void)
{
    return 32;
}

int set_pelt_halflife(int num)
{
    /* Add implementation here */
    return 0;
}