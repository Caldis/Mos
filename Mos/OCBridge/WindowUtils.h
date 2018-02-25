//
//  WindowUtils.h
//  Mos
//  [OC 方法封装] 获取窗口信息
//  Created by Caldis on 2018/2/25.
//  Copyright © 2018年 Caldis. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#ifndef WindowUtils_h
#define WindowUtils_h

@interface WindowUtils : NSObject
    
+(NSDictionary*)getWindowDataFrom:(CGEventRef)event;
    
@end

#endif /* WindowUtils_h */
