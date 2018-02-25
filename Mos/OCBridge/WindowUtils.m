//
//  WindowUtils.m
//  Mos
//  [OC 方法封装] 获取窗口信息
//  Created by Caldis on 2018/2/25.
//  Copyright © 2018年 Caldis. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WindowUtils.h"

@implementation WindowUtils
    
// 获取鼠标当前位置的顶层窗口信息
+(NSDictionary*)getWindowDataFrom:(CGEventRef)event {
    // 获取鼠标当前位置的顶层窗口的 windowNumber
    CGPoint location = CGEventGetLocation(event);
    NSInteger windowNumber = [NSWindow windowNumberAtPoint:location belowWindowWithWindowNumber:0];
    // 从 windowNumber 获取窗口信息
    CGWindowID windowID = (CGWindowID)windowNumber;
    CFArrayRef array = CFArrayCreate(NULL, (const void **)&windowID, 1, NULL);
    NSArray *windowInfos = (NSArray *)CFBridgingRelease(CGWindowListCreateDescriptionFromArray(array));
    CFRelease(array);
    // 返回数据
    if (windowInfos.count > 0) {
        NSDictionary *windowInfo = [windowInfos objectAtIndex:0];
        return windowInfo;
    }
    return nil;
}
    
@end
