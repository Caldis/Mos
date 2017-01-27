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

// CGWheelCount type = 2; // 1 for Y-only, 2 for Y-X, 3 for Y-X-Z
// int32_t xScroll = −1; // Negative for right
// int32_t yScroll = −2; // Negative for down
-(void)scroll:(uint32_t)type yScroll:(int32_t)yScroll xScroll:(int32_t)xScroll {
    CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, type, yScroll, xScroll);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, 1);
    CGEventPost(kCGSessionEventTap, event);
}

@end
