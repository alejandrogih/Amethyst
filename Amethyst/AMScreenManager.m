//
//  AMScreenManager.m
//  Amethyst
//
//  Created by Ian on 5/19/13.
//  Copyright (c) 2013 Ian Ynda-Hummel. All rights reserved.
//

#import "AMScreenManager.h"

#import "Amethyst-Swift.h"

#import "AMConfiguration.h"
#import "AMLayoutNameWindow.h"
#import "AMWindowManager.h"

@interface AMScreenManager ()
@property (nonatomic, strong) NSString *screenIdentifier;

@property (nonatomic, strong) NSTimer *reflowTimer;
@property (nonatomic, strong) ReflowOperation *reflowOperation;

@property (nonatomic, copy) NSArray *layouts;
@property (nonatomic, strong) NSMutableDictionary *currentLayoutIndexBySpaceIdentifier;
@property (nonatomic, strong) NSMutableDictionary *layoutsBySpaceIdentifier;
@property (nonatomic, assign) NSUInteger currentLayoutIndex;
- (Layout *)currentLayout;

@property (nonatomic, strong) AMLayoutNameWindow *layoutNameWindow;

@property (nonatomic, assign) BOOL changingSpace;
@end

@implementation AMScreenManager

#pragma mark Lifecycle

- (id)init { return nil; }

- (id)initWithScreen:(NSScreen *)screen managedDisplay:(NSString *)screenIdentifier delegate:(id<AMScreenManagerDelegate>)delegate {
    self = [super init];
    if (self) {
        self.delegate = delegate;

        self.screen = screen;
        self.screenIdentifier = screenIdentifier;

        self.layouts = [[AMConfiguration sharedConfiguration] layoutsWithWindowActivityCache:self];
        self.currentLayoutIndexBySpaceIdentifier = [NSMutableDictionary dictionary];
        self.layoutsBySpaceIdentifier = [NSMutableDictionary dictionary];
        self.currentLayoutIndex = 0;

        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"AMLayoutNameWindow" bundle:nil];
        NSArray *objects;

        [nib instantiateWithOwner:nil topLevelObjects:&objects];

        for (id object in objects) {
            if ([object isKindOfClass:AMLayoutNameWindow.class]) {
                self.layoutNameWindow = object;
            }
        }

        [self hideLayoutHUD:nil];

        @weakify(self);
        [RACObserve(self, currentLayoutIndex) subscribeNext:^(NSNumber *currentLayoutIndex) {
            @strongify(self);

            if (!self.changingSpace || [[AMConfiguration sharedConfiguration] enablesLayoutHUDOnSpaceChange]) {
                [self displayLayoutHUD];
            }
        }];
    }
    return self;
}

- (void)setCurrentSpaceIdentifier:(NSString *)currentSpaceIdentifier {
    if ([_currentSpaceIdentifier isEqualToString:currentSpaceIdentifier]) return;

    if (_currentSpaceIdentifier) {
        self.currentLayoutIndexBySpaceIdentifier[_currentSpaceIdentifier] = @(self.currentLayoutIndex);
    }

    _currentSpaceIdentifier = currentSpaceIdentifier;

    if (_currentSpaceIdentifier) {
        self.changingSpace = YES;
        self.currentLayoutIndex = [self.currentLayoutIndexBySpaceIdentifier[_currentSpaceIdentifier] integerValue];
        if (self.layoutsBySpaceIdentifier[_currentSpaceIdentifier]) {
            self.layouts = self.layoutsBySpaceIdentifier[_currentSpaceIdentifier];
        } else {
            self.layouts = [[AMConfiguration sharedConfiguration] layoutsWithWindowActivityCache:self];
            self.layoutsBySpaceIdentifier[_currentSpaceIdentifier] = self.layouts;
        }
    }

    [self setNeedsReflow];
}

- (void)displayLayoutHUD {
    if (![[AMConfiguration sharedConfiguration] enablesLayoutHUD]) {
        return;
    }

    CGRect screenFrame = self.screen.frame;
    CGPoint screenCenter = (CGPoint){
        .x = CGRectGetMidX(screenFrame),
        .y = CGRectGetMidY(screenFrame)
    };
    CGPoint windowOrigin = (CGPoint){
        .x = screenCenter.x - self.layoutNameWindow.frame.size.width / 2.0,
        .y = screenCenter.y - self.layoutNameWindow.frame.size.height / 2.0,
    };

    self.layoutNameWindow.layoutNameField.stringValue = [self.currentLayout.class layoutName];
    [self.layoutNameWindow setFrameOrigin:NSPointFromCGPoint(windowOrigin)];
    [self.layoutNameWindow makeKeyAndOrderFront:NSApp];

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideLayoutHUD:) object:nil];
    [self performSelector:@selector(hideLayoutHUD:) withObject:nil afterDelay:0.6];
}

- (void)hideLayoutHUD:(id)sender {
    [self.layoutNameWindow close];
}

- (void)setNeedsReflow {
    [self.reflowOperation cancel];
    if (self.changingSpace) {
        // The 0.4 is disgustingly tied to the space change animation time.
        // This should get burned to the ground when space changes don't rely on the mouse click trick.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reflow:nil];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reflow:nil];
        });
    }
}

- (void)reflow:(id)sender {
    if (!self.currentSpaceIdentifier) return;
    if (self.currentLayoutIndex >= self.layouts.count) return;
    if (![AMConfiguration sharedConfiguration].tilingEnabled) return;
    if (self.isFullScreen) return;
    if (CGSManagedDisplayIsAnimating(CGSDefaultConnection, (__bridge CGSManagedDisplay)self.screenIdentifier)) return;

    self.changingSpace = NO;
    self.reflowOperation = [self.layouts[self.currentLayoutIndex] reflowOperationForScreen:self.screen withWindows:[self.delegate activeWindowsForScreenManager:self]];
    [[NSOperationQueue mainQueue] addOperation:self.reflowOperation];
}

- (void)updateCurrentLayout:(AMScreenManagerLayoutUpdater)updater {
    updater(self.currentLayout);
    [self setNeedsReflow];
}

- (Layout *)currentLayout {
    return self.layouts[self.currentLayoutIndex];
}

- (void)cycleLayoutForward {
    self.currentLayoutIndex = (self.currentLayoutIndex + 1) % self.layouts.count;
    [self setNeedsReflow];
}

- (void)cycleLayoutBackward {
    self.currentLayoutIndex = (self.currentLayoutIndex == 0 ? self.layouts.count : self.currentLayoutIndex) - 1;
    [self setNeedsReflow];
}

- (void)selectLayout:(Class)layoutClass {
    NSInteger layoutIndex = [self.layouts indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop) {
        return [obj isKindOfClass:layoutClass];
    }];
    if (layoutIndex == NSNotFound) return;

    self.currentLayoutIndex = layoutIndex;
    [self setNeedsReflow];
}

- (void)shrinkMainPane {
    [self.currentLayout shrinkMainPane];
    [self setNeedsReflow];
}

- (void)expandMainPane {
    [self.currentLayout expandMainPane];
    [self setNeedsReflow];
}

- (BOOL)windowIsActive:(SIWindow *)window {
    if (!window.isActive || !self.activeIDCache[@(window.windowID)]) {
        return NO;
    }
    return YES;
}

@end
