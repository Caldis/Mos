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

// 处理鼠标事件的方向
// 创建一个鼠标滚轮事件. 并直接发送到 kCGSessionEventTap 层
// dimension: 事件包含的轴, 1 for Y or X only, 2 for Y-X, 3 for Y-X-Z
// yScroll: y 轴数据
// xScroll: x 轴数据
+(void)scroll:(uint32_t)dimension yScroll:(int32_t)yScroll xScroll:(int32_t)xScroll {
    // 创建事件
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, dimension, yScroll, xScroll);
    // 设置事件属性
    CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, 1);
//    CGEventSetIntegerValueField(event, kCGGesturePhase, kCGGesturePhaseNone);
    // 发送事件
    CGEventPost(kCGSessionEventTap, event);
    // 释放
    // https://github.com/Caldis/Mos/issues/85
    CFRelease(event);
}

// 同上, 多设置几个属性
+(void)scroll:(uint32_t)dimension yScroll:(int32_t)yScroll xScroll:(int32_t)xScroll scrollPhase:(int32_t)scrollPhase momentumPhase:(int32_t)momentumPhase {
    // 创建事件
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, dimension, yScroll, xScroll);
    // 设置事件属性
     CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, 1);
    // 部分应用需要此属性以模拟触控板触发事件，但会引起 Chrome 不识别滚动，需要进一步模拟各阶段参数
    CGEventSetIntegerValueField(event, kCGScrollWheelEventScrollPhase, scrollPhase);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventMomentumPhase, momentumPhase);
    // 发送事件
    CGEventPost(kCGSessionEventTap, event);
    // 释放
    // https://github.com/Caldis/Mos/issues/85
    CFRelease(event);
}

@end
