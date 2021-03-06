//
//  RXLogCenter.m
//  rivenx
//
//  Created by Jean-Francois Roy on 26/02/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import <unistd.h>
#import <errno.h>
#import <asl.h>

#import "Base/RXLogCenter.h"

#import "Base/RXErrors.h"
#import "Base/RXLogging.h"

#import "Utilities/BZFSUtilities.h"

#import <CoreServices/CoreServices.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSPathUtilities.h>


@implementation RXLogCenter

+ (RXLogCenter*)sharedLogCenter
{
    static RXLogCenter* center = nil;
    if (center == nil)
        center = [RXLogCenter new];
    return center;
}

- (id)init
{
    self = [super init];
    if (!self)
        return nil;
    
    NSError* error = nil;
    
    // logs are put in the user's Logs folder
    FSRef logsFolder;
    OSErr oerr = FSFindFolder(kUserDomain, kLogsFolderType, true, &logsFolder);
    if (oerr != noErr)
    {
        error = [RXError errorWithDomain:NSOSStatusErrorDomain code:oerr userInfo:nil];
        @throw [NSException exceptionWithName:@"RXFilesystemException" reason:@"Riven X was unable to find your logs folder."
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    
    NSURL* logsURL = [(NSURL*)CFURLCreateFromFSRef(NULL, &logsFolder) autorelease];
    _logsBase = [[[logsURL path] stringByAppendingPathComponent:@"Riven X"] retain];
    if (!BZFSDirectoryExists(_logsBase))
    {
        BOOL success = BZFSCreateDirectory(_logsBase, &error);
        if (!success)
            @throw [NSException exceptionWithName:@"RXFilesystemException" reason:@"Riven X was unable to create its logs folder in your Logs folder."
                userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    
    // map facilities to certain log files
    _facilityFDMap = [NSMutableDictionary new];
    pthread_mutex_init(&_facilityFDMapMutex, NULL);
     
    // FIXME: better way than hardcoding facilities to log files
    int fd;
    NSFileHandle* fh;
    
    fd = open([[_logsBase stringByAppendingPathComponent:@"Rendering.log"] fileSystemRepresentation], O_WRONLY | O_APPEND | O_TRUNC | O_CREAT, 0600);
    if (fd == -1)
    {
        error = [RXError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        @throw [NSException exceptionWithName:@"RXFilesystemException" reason:@"Riven X was unable to create a log file."
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    fh = [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease];
    [_facilityFDMap setObject:fh forKey:[NSString stringWithCString:kRXLoggingRendering encoding:NSASCIIStringEncoding]];
    [_facilityFDMap setObject:fh forKey:[NSString stringWithCString:kRXLoggingGraphics encoding:NSASCIIStringEncoding]];
    [_facilityFDMap setObject:fh forKey:[NSString stringWithCString:kRXLoggingAudio encoding:NSASCIIStringEncoding]];
    
    fd = open([[_logsBase stringByAppendingPathComponent:@"Script.log"] fileSystemRepresentation], O_WRONLY | O_APPEND | O_TRUNC | O_CREAT, 0600);
    if (fd == -1)
    {
        error = [RXError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        @throw [NSException exceptionWithName:@"RXFilesystemException" reason:@"Riven X was unable to create a log file."
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    fh = [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease];
    [_facilityFDMap setObject:fh forKey:[NSString stringWithCString:kRXLoggingScript encoding:NSASCIIStringEncoding]];
    
    fd = open([[_logsBase stringByAppendingPathComponent:@"Base.log"] fileSystemRepresentation], O_WRONLY | O_APPEND | O_TRUNC | O_CREAT, 0600);
    if (fd == -1)
    {
        error = [RXError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        @throw [NSException exceptionWithName:@"RXFilesystemException" reason:@"Riven X was unable to create a log file."
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    fh = [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease];
    [_facilityFDMap setObject:fh forKey:[NSString stringWithCString:kRXLoggingBase encoding:NSASCIIStringEncoding]];
    
    fd = open([[_logsBase stringByAppendingPathComponent:@"Audio.log"] fileSystemRepresentation], O_WRONLY | O_APPEND | O_TRUNC | O_CREAT, 0600);
    if (fd == -1)
    {
        error = [RXError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        @throw [NSException exceptionWithName:@"RXFilesystemException" reason:@"Riven X was unable to create a log file."
            userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    }
    fh = [[[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES] autorelease];
    [_facilityFDMap setObject:fh forKey:[NSString stringWithCString:kRXLoggingAudio encoding:NSASCIIStringEncoding]];
     
    // open a generic log file
    _genericLogFD = open([[_logsBase stringByAppendingPathComponent:@"Riven X.log"] fileSystemRepresentation], O_WRONLY | O_APPEND | O_TRUNC | O_CREAT, 0600);
    
    _levelFilter = ASL_FILTER_MASK_UPTO(ASL_LEVEL_NOTICE);
#if defined(DEBUG)
    _levelFilter = ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG);
#endif
    
    _didInit = YES;
    return self;
}

- (void)dealloc
{
    [self tearDown];
    
    [_logsBase release];
    
    [_facilityFDMap release];
    pthread_mutex_destroy(&_facilityFDMapMutex);
    
    [super dealloc];
}

- (void)tearDown
{
    if (_toreDown)
        return;
    _toreDown = YES;
    
    [_facilityFDMap removeAllObjects];
    close(_genericLogFD);
}

- (void)_openLogFileForFacility:(NSString*)facility
{
    
}

- (void)log:(NSString*)message facility:(NSString*)facility level:(int)level
{
    if (_toreDown)
        return;
    
    // check against the level filter
    if ((ASL_FILTER_MASK(level) & _levelFilter) == 0)
        return;
    
    // message data as UTF-8
    NSData* messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
    
    // write to all appropriate log files
    NSFileHandle* fh = [_facilityFDMap objectForKey:facility];
    if (fh)
        write([fh fileDescriptor], [messageData bytes], [messageData length]);
    
    // always write to the generic log
    write(_genericLogFD, [messageData bytes], [messageData length]);
    
    // echo base message and error or more serious messages to stderr
    if ([[NSString stringWithCString:kRXLoggingBase encoding:NSASCIIStringEncoding] isEqualToString:facility] || level <= kRXLoggingLevelError)
        write(STDERR_FILENO, [messageData bytes], [messageData length]);
}

@end
