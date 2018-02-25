//
//  ProcessUtils.m
//  Mos
//  [OC 方法封装] 从进程获取其父进程 pid
//  Created by Caldis on 24/8/17.
//  Copyright © 2017年 Caldis. All rights reserved.
//

#import <sys/sysctl.h>
#import "ProcessUtils.h"
#define OPProcessValueUnknown UINT_MAX

@implementation ProcessUtils

+(int)getParentPidFrom:(int)pid {
    struct kinfo_proc info;
    size_t length = sizeof(struct kinfo_proc);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
        return OPProcessValueUnknown;
    if (length == 0)
        return OPProcessValueUnknown;
    return (int)info.kp_eproc.e_ppid;
}

@end
