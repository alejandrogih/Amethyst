//
//  AMWindow.h
//  Amethyst
//
//  Created by Ian on 5/16/13.
//  Copyright (c) 2013 Ian Ynda-Hummel. All rights reserved.
//

#import "AMAccessibilityElement.h"

@interface AMWindow : AMAccessibilityElement

- (BOOL)isHidden;
- (BOOL)isMinimized;
- (BOOL)isResizable;

- (CGRect)frame;
- (void)setFrame:(CGRect)frame;

- (NSScreen *)screen;

@end