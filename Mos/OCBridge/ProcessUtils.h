//
//  ProcessUtils.h
//  Mos
//  [OC 方法封装] 从进程获取其父进程 pid
//  Created by Caldis on 24/8/17.
//  Copyright © 2017年 Caldis. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#ifndef ProcessUtils_h
#define ProcessUtils_h

@interface ProcessUtils : NSObject

+(int)getParentPidFrom:(int)pid;

@end

#endif /* ProcessUtils_h */
