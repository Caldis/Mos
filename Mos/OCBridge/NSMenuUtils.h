//
//  NSMenuUtils.h
//  Mos
//  [OC 方法封装(私有方法)] 隐藏 NSMenu 的 padding
//  Created by Caldis on 2018/3/4.
//  Copyright © 2018年 Caldis. All rights reserved.
//

#ifndef NSMenuUtils_h
#define NSMenuUtils_h

@interface NSMenu (secret)

// Use NSMaxYEdge to toggle the top padding
// and NSMinYEdge to toggle the bottom one
-(void)_setHasPadding:(BOOL)pad onEdge:(int)whatEdge;

@end

#endif /* NSMenuUtils_h */
