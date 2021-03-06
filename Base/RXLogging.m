/*
 *  RXLogging.m
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 26/02/2008.
 *  Copyright 2005-2012 MacStorm. All rights reserved.
 *
 */

#import <asl.h>

#import "RXLogging.h"
#import "RXLogCenter.h"
#import "RXThreadUtilities.h"


/* facilities */
const char* kRXLoggingBase = "BASE";
const char* kRXLoggingEngine = "ENGINE";
const char* kRXLoggingRendering = "RENDERING";
const char* kRXLoggingScript = "SCRIPT";
const char* kRXLoggingGraphics = "GRAPHICS";
const char* kRXLoggingAudio = "AUDIO";
const char* kRXLoggingEvents = "EVENTS";
const char* kRXLoggingAnimation = "ANIMATION";

/* levels */
const int kRXLoggingLevelDebug = ASL_LEVEL_DEBUG;
const int kRXLoggingLevelMessage = ASL_LEVEL_NOTICE;
const int kRXLoggingLevelError = ASL_LEVEL_ERR;
const int kRXLoggingLevelCritical = ASL_LEVEL_CRIT;

static NSString* RX_log_format = @"%@ [%s] [%@] %@\n";

void RXCFLog(const char* facility, int level, CFStringRef format, ...) {
    va_list args;
    va_start(args, format);
    
    CFStringRef userString = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL, format, args);
    CFStringRef facilityString = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, facility, NSASCIIStringEncoding, kCFAllocatorNull);
    CFDateRef now = CFDateCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent());
    
    char* threadName = RXCopyThreadName();
    
    CFStringRef logString = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, (CFStringRef)RX_log_format, now, threadName, facilityString, userString);
    [[RXLogCenter sharedLogCenter] log:(NSString*)logString facility:(NSString*)facilityString level:level];
    
    free(threadName);
    CFRelease(logString);
    CFRelease(now);
    CFRelease(facilityString);
    CFRelease(userString);
    
    va_end(args);
}

void RXLog(const char* facility, int level, NSString* format, ...) {
    va_list args;
    va_start(args, format);
    RXLogv(facility, level, format, args);
    va_end(args);
}

void RXLogv(const char* facility, int level, NSString* format, va_list args) {
    NSString* userString = [[NSString alloc] initWithFormat:format arguments:args];
    NSString* facilityString = [[NSString alloc] initWithCString:facility encoding:NSASCIIStringEncoding];
    NSDate* now = [NSDate new];
    
    char* threadName = RXCopyThreadName();
    
    NSString* logString = [[NSString alloc] initWithFormat:RX_log_format, now, threadName, facilityString, userString];
    [[RXLogCenter sharedLogCenter] log:logString facility:facilityString level:level];
    
    free(threadName);
    [logString release];
    [now release];
    [facilityString release];
    [userString release];
}

void _RXOLog(id object, const char* facility, int level, NSString* format, ...) {
    va_list args;
    va_start(args, format);
    
    NSString* finalFormat = [[NSString alloc] initWithFormat:@"%@: %@", [object description], format];
    RXLogv(facility, level, finalFormat, args);
    
    va_end(args);
    [finalFormat release];
}
