//
//  MouseEvent.m
//  Mos
//  [OC 方法封装] 发送鼠标事件
//  Created by Caldis on 2017/1/17.
//  Copyright © 2017年 Caldis. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MouseEvent.h"

@implementation MouseEvent

// 创建一个鼠标滚轮事件. 并直接发送到 kCGSessionEventTap 层
// CGWheelCount type = 2; // 事件包含的轴数量, 1 for Y or X only, 2 for Y-X, 3 for Y-X-Z
// int32_t xScroll = −1;  // Negative for right
// int32_t yScroll = −1;  // Negative for down
+(void)scroll:(uint32_t)type yScroll:(int32_t)yScroll xScroll:(int32_t)xScroll {
    // 创建事件
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, type, yScroll, xScroll);
    // 设置目标
    CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, 1);
    // 发送事件
    CGEventPost(kCGSessionEventTap, event);
}

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

