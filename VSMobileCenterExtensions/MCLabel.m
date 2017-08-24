
#import <XCTest/XCTest.h>
#import "MCLabel.h"

/*
 This label prefix signifies to the event processor that this particular log
 statement is intended to be treated as a label.
 */
const NSString *LABEL_PREFIX = @"[MobileCenterTest]: ";

/*
 We need some references to private API methods, so we'll declare them here.
 */
@interface XCAXClient_iOS : NSObject
+ (XCAXClient_iOS *)sharedClient;
- (NSData *)screenshotData;
@end

@interface XCActivityRecord : NSObject
@property (copy) NSData *screenImageData;
@property (copy) NSString *title;

// Xcode 9; not sure which is correct.
- (void)addAttachment:(id)attachment;
- (void)addScreenImageData:(id)data;
@end

@interface _XCTestCaseImplementation : NSObject
@property(retain, nonatomic) NSMutableArray <XCActivityRecord *> *activityRecordStack;
@end

typedef void (^activityBlock)(XCActivityRecord *activityRecord);

@interface XCTestCase (MCTAccess)
@property(retain) _XCTestCaseImplementation *internalImplementation;
- (void)startActivityWithTitle:(NSString *)title block:(activityBlock)block;
@end

XCTestCase *_XCTCurrentTestCase();
void _XCINFLog(NSString *msg);

@implementation MCLabel

+ (void)label:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    [self labelStep:fmt args:args];
    va_end(args);
}

+ (XCTestCase *)currentTestCase {
    return _XCTCurrentTestCase();
}

+ (void)labelStep:(NSString *)msg {
    [self _label:msg];
}

+ (void)labelStep:(NSString *)fmt args:(va_list)args {
    NSString *lbl = [[NSString alloc] initWithFormat:fmt arguments:args];
    [self _label:lbl];
}

+ (void)labelFailedWithError:(NSString *)errorMessage labelMessage:(NSString *)labelMessage {
    /*
     These will appear in the Device Log.
     */
    NSLog(@"%@ERROR: %@", LABEL_PREFIX, errorMessage);
    NSLog(@"%@ERROR: Unable to process label(\"%@\")", LABEL_PREFIX, labelMessage);

    /*
     These will appear in the Debug Log of the test run.
     */
    _XCINFLog([NSString stringWithFormat:@"%@ERROR: %@", LABEL_PREFIX, errorMessage]);
    _XCINFLog([NSString stringWithFormat:@"%@ERROR: Unable to process label(\"%@\")", LABEL_PREFIX, labelMessage]);
}

+ (void)attachScreenshotUsingAXClientToActivityRecord:(XCActivityRecord *)activityRecord
                                             testCase:(XCTestCase *)testCase
                                              message:(NSString *)message {

    XCAXClient_iOS *client = [XCAXClient_iOS sharedClient];
    if (!client) {
        [MCLabel labelFailedWithError:@"Unable to fetch Accessibility Client."
                         labelMessage:message];
    } else {
        NSData *screenshotData = [client screenshotData];
        if (!screenshotData) {
            [MCLabel labelFailedWithError:@"Unable to fetch screenshot data from Accessibility Client."
                          labelMessage:message];
        } else {
            [activityRecord setScreenImageData:screenshotData];
        }
    }
}

+ (id)XCIUMainScreen {
    Class klass = NSClassFromString(@"XCUIScreen");
    SEL selector = NSSelectorFromString(@"mainScreen");

    NSMethodSignature *signature;
    signature = [klass methodSignatureForSelector:selector];
    NSInvocation *invocation;

    invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = klass;
    invocation.selector = selector;

    id mainScreen = nil;
    void *buffer;
    [invocation performSelectorOnMainThread:@selector(invoke)
                                 withObject:nil
                              waitUntilDone:YES];
    [invocation getReturnValue:&buffer];
    mainScreen = (__bridge id)buffer;
    return mainScreen;
}

+ (NSData *)screenshotWithXCUIMainScreen:(id)mainScreen {
    SEL selector = NSSelectorFromString(@"screenshot");
    NSMethodSignature *signature;
    signature = [mainScreen instanceMethodSignatureForSelector:selector];
    NSInvocation *invocation;

    invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = mainScreen;
    invocation.selector = selector;

    NSData *data = nil;
    void *buffer;
    [invocation performSelectorOnMainThread:@selector(invoke)
                                 withObject:nil
                              waitUntilDone:YES];
    [invocation getReturnValue:&buffer];
    data = (__bridge NSData *)buffer;
    return data;
}

+ (id)XCTAttachmentWithScreenshot:(NSData *)screenshot {
    Class klass = NSClassFromString(@"XCTAttachment");
    SEL selector = NSSelectorFromString(@"attachmentWithScreenshot:");

    NSMethodSignature *signature;
    signature = [klass methodSignatureForSelector:selector];
    NSInvocation *invocation;

    invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = klass;
    invocation.selector = selector;

    id attachment = nil;
    void *buffer;
    [invocation performSelectorOnMainThread:@selector(invoke)
                                 withObject:nil
                              waitUntilDone:YES];
    [invocation getReturnValue:&buffer];
    attachment = (__bridge id)buffer;
    return attachment;
}

+ (void)attachScreenshotUsingXCUIScreenToActivityRecord:(XCActivityRecord *)activityRecord
                                               testCase:(XCTestCase *)testCase
                                                message:(NSString *)message {
    id XCUIScreenMainScreen = [MCLabel XCIUMainScreen];
    if (!XCUIScreenMainScreen) {
        [MCLabel labelFailedWithError:@"Unable to fetch XCUIScreen.mainScreen"
                         labelMessage:message];
    } else {
        NSData *screenshotData = [MCLabel screenshotWithXCUIMainScreen:XCUIScreenMainScreen];
        if (!screenshotData) {
            [MCLabel labelFailedWithError:@"Unable to fetch screenshot data XCUIScreen.mainScreen"
                             labelMessage:message];
        } else {

            /*
             Which one...
             000000000002803c t -[XCActivityRecord addAttachment:]
             0000000000027c1c t -[XCActivityRecord addScreenImageData:]
            */
            id attachment = [MCLabel XCTAttachmentWithScreenshot:screenshotData];
            [activityRecord addAttachment:attachment];
            // Need to set attachment lifetime to "keepAlways"
        }
    }
}

+ (void)attachScreenshotToActivityRecord:(XCActivityRecord *)activityRecord
                                testCase:(XCTestCase *)testCase
                                 message:(NSString *)message {
    if (NSClassFromString(@"XCUIScreen")) {
        [MCLabel attachScreenshotUsingXCUIScreenToActivityRecord:activityRecord
                                                        testCase:testCase
                                                         message:message];
    } else {
        [MCLabel attachScreenshotUsingAXClientToActivityRecord:activityRecord
                                                      testCase:testCase
                                                       message:message];
    }
}

/*
 We add in the prefix and pass it along to XCTest
 */
+ (void)_label:(NSString *)message {
    XCTestCase *testCase = [self currentTestCase];
    if (testCase == nil) {
        [MCLabel labelFailedWithError:@"Unable to locate current test case."
                      labelMessage:message];
    } else {
        /*
         Declare that we are starting an activity, titled with the user's label.
         This activity merely captures a screenshot, which is then processed
         by MobileCenter/XTC.
         */
        [testCase startActivityWithTitle:[NSString stringWithFormat:@"%@%@", LABEL_PREFIX, message]
                                   block:^(XCActivityRecord *activityRecord) {
                                       if (activityRecord == nil) {
                                           [MCLabel labelFailedWithError:@"No XCActivityRecord currently exists."
                                                            labelMessage:message];
                                       } else {
                                           [MCLabel attachScreenshotToActivityRecord:activityRecord
                                                                            testCase:testCase
                                                                             message:message];
                                       }
                                   }];
    }
}

@end
