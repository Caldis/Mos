//
//  MouseEvent.m
//  Mos
//  用于封装OC中CGEventCreateScrollWheelEvent事件, Swift中缺失这个事件
//  Created by Cb on 2017/1/17.
//  Copyright © 2017年 Cb. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MouseEvent.h"

@implementation MouseEvent

// 创建一个鼠标滚轮事件. 并直接发送到kCGSessionEventTap层
// CGWheelCount type = 2; // 1 for Y-only, 2 for Y-X, 3 for Y-X-Z
// int32_t xScroll = −1; // Negative for right
// int32_t yScroll = −2; // Negative for down
+(void)scroll:(uint32_t)type yScroll:(int32_t)yScroll xScroll:(int32_t)xScroll {
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, type, yScroll, xScroll);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, 1);
    CGEventPost(kCGSessionEventTap, event);
}

// 获取鼠标当前位置的顶层窗口信息 (废弃, 无法获取外接屏幕的窗口信息)
// var eventTargetOwnerName:String!
// if let eventTargetWindowData = MouseEvent.getWindowData(from: event) {
//     eventTargetOwnerName = eventTargetWindowData["kCGWindowOwnerName"] as! String
// }
// kCGWindowName: 窗口标题
// kCGWindowOwnerName: 窗口进程名
// windowInfo结构:
// Optional([
//     AnyHashable("kCGWindowMemoryUsage"): 1072,
//     AnyHashable("kCGWindowOwnerPID"): 615,
//     AnyHashable("kCGWindowStoreType"): 1,
//     AnyHashable("kCGWindowBounds"): {
//         Height = 894;
//         Width = 1492;
//         X = 43;
//         Y = 54;
//     },
//     AnyHashable("kCGWindowSharingState"): 1,
//     AnyHashable("kCGWindowIsOnscreen"): 1,
//     AnyHashable("kCGWindowOwnerName"): Safari,
//     AnyHashable("kCGWindowName"): NSDictionary - Foundation | Apple Developer Documentation, AnyHashable("kCGWindowLayer"): 0,
//     AnyHashable("kCGWindowNumber"): 6617, AnyHashable("kCGWindowAlpha"): 1
// ])
+(NSDictionary*)getWindowDataFrom:(CGEventRef)event {
    // 获取鼠标当前位置的顶层窗口的windowNumber
    CGPoint location = CGEventGetLocation(event);
    NSInteger windowNumber = [NSWindow windowNumberAtPoint:location belowWindowWithWindowNumber:0];
    // 从windowNumber获取窗口信息
    CGWindowID windowID = (CGWindowID)windowNumber;
    CFArrayRef array = CFArrayCreate(NULL, (const void **)&windowID, 1, NULL);
    NSArray *windowInfos = (NSArray *)CFBridgingRelease(CGWindowListCreateDescriptionFromArray(array));
    CFRelease(array);
    // 如果有数据, 则返回
    if (windowInfos.count > 0) {
        NSDictionary *windowInfo = [windowInfos objectAtIndex:0];
        return windowInfo;
    }
    return nil;
}

@end
