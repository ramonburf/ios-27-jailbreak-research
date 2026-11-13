#import <mach-o/dyld.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

int trigger_ane_direct(void);
void run_decmpfs_leak(const char *base_dir);
void log_from_c(const char* msg);
void run_iosurface_notify_probe(void);

// Container-manager extension probe (see WQProbe.c).
#include <stdint.h>
int64_t wq_grant(const char *target, const char *group, uint64_t flags);
void wq_revoke(int64_t handle);
int wq_group_available(const char *group);
int64_t wq_token(const char *identifier, uint64_t cls, uint64_t part, uint64_t flags, const char *partDomain);

