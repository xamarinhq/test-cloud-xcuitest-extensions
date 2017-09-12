
#import "MCLaunch.h"
#import <XCTest/XCTest.h>
#import <objc/runtime.h>


@implementation MCLaunch

+ (XCUIApplication *)launch {
    XCUIApplication *application = [[XCUIApplication alloc] init];
    [application launch];
    return application;
}

+ (XCUIApplication *)launchApplication:(XCUIApplication *)application {
    [application launch];
    return application;
}

+ (id)XCUIApplicationImpl:(XCUIApplication *)application {
    Class klass = [application class];
    SEL selector = NSSelectorFromString(@"applicationImpl");

    NSMethodSignature *signature;
    signature = [klass instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation;

    invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = application;
    invocation.selector = selector;

    id applicationImpl = nil;
    void *buffer;

    [invocation performSelectorOnMainThread:@selector(invoke)
                                 withObject:nil
                              waitUntilDone:YES];

    [invocation getReturnValue:&buffer];
    applicationImpl = (__bridge id)buffer;
    return applicationImpl;
}

+ (void)XCUIApplicationImpl:(id)applicationImpl
setSupportAutomationSession:(BOOL)value {
    SEL selector = NSSelectorFromString(@"setSupportsAutomationSession:");

    if (![applicationImpl respondsToSelector:selector]) {
        NSLog(@"XCUIApplicationImpl does not respond to %@",
              NSStringFromSelector(selector));
        return;
    }

    Class klass = [applicationImpl class];

    NSMethodSignature *signature;
    signature = [klass instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation;

    invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = applicationImpl;
    invocation.selector = selector;

    [invocation setArgument:&value atIndex:2];

    [invocation performSelectorOnMainThread:@selector(invoke)
                                 withObject:nil
                              waitUntilDone:YES];
}

+ (void)turnOffAutomationSession:(id)XCUIApplication {
    id applicationImpl = [MCLaunch XCUIApplicationImpl:XCUIApplication];
    [MCLaunch XCUIApplicationImpl:applicationImpl
      setSupportAutomationSession:NO];
}

+ (XCUIApplicationState)stateForApplication:(XCUIApplication *)application {
    SEL selector = NSSelectorFromString(@"state");
    if ([application respondsToSelector:selector]) {
        Class klass = [application class];
        NSMethodSignature *signature;
        signature = [klass instanceMethodSignatureForSelector:selector];
        NSInvocation *invocation;

        invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = application;
        invocation.selector = selector;

        void *buffer;
        [invocation performSelectorOnMainThread:@selector(invoke)
                                     withObject:nil
                                  waitUntilDone:YES];

        [invocation getReturnValue:&buffer];
        return (XCUIApplicationState)buffer;
    } else {
        return XCUIApplicationStateUnknown;
    }
}

@end

typedef void (*OriginalLaunchImpType)(id self, SEL selector);
static OriginalLaunchImpType originalLaunchImp;

@interface XCUIApplication (MobileCenterAdditions)

- (void)swizzled_launch;

@end

@implementation XCUIApplication (MobileCenterAdditions)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class klass = [self class];

        SEL originalSelector = NSSelectorFromString(@"launch");
        SEL swizzledSelector = NSSelectorFromString(@"swizzled_launch");

        Method originalMethod = class_getInstanceMethod(klass, originalSelector);
        originalLaunchImp = (OriginalLaunchImpType)method_getImplementation(originalMethod);
        Method swizzledMethod = class_getInstanceMethod(klass, swizzledSelector);

        BOOL didAddMethod =
        class_addMethod(klass,
                        originalSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(klass,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (void)swizzled_launch {
    [MCLaunch turnOffAutomationSession:self];
    originalLaunchImp(self, @selector(launch));
}

@end
