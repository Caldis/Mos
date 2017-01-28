//
//  MouseEvent.h
//  Mos
//  用于封装OC中CGEventCreateScrollWheelEvent事件, Swift中缺失这个事件
//  Created by Cb on 2017/1/17.
//  Copyright © 2017年 Cb. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#ifndef MouseEvent_h
#define MouseEvent_h

@interface MouseEvent : NSObject

+(void)scroll:(uint32_t)wheelCount yScroll:(int32_t)yScroll xScroll:(int32_t)xScroll;
+(NSDictionary*)getWindowDataFrom:(CGEventRef)event;

@end

#endif /* MouseEvent_h */
