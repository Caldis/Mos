//
//  MouseEvent.h
//  Mos
//  [OC 方法封装] 发送鼠标事件
//  Created by Cb on 2017/1/17.
//  Copyright © 2017年 Cb. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#ifndef MouseEvent_h
#define MouseEvent_h

@interface MouseEvent : NSObject

+(void)scroll:(uint32_t)dimension yScroll:(int32_t)yScroll xScroll:(int32_t)xScroll;

@end

#endif /* MouseEvent_h */
