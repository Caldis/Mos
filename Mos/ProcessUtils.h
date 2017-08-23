//
//  ProcessUtils.h
//  Mos
//  用于封装 OC 的进程处理方法 - 从子进程获取父进程 pid
//  Created by Cb on 24/8/17.
//  Copyright © 2017年 Cb. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#ifndef ProcessUtils_h
#define ProcessUtils_h

@interface ProcessUtils : NSObject
    
+(int)getParentPidFrom:(int)pid;
    
@end

#endif /* ProcessUtils_h */
