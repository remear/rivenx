//
//  RXEditionManager.m
//  rivenx
//
//  Created by Jean-Francois Roy on 02/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import <Carbon/Carbon.h>

#import "Engine/RXEditionManager.h"
#import "Engine/RXWorld.h"

#import "Utilities/BZFSUtilities.h"
#import "Utilities/GTMObjectSingleton.h"


@implementation RXEditionManager

GTMOBJECT_SINGLETON_BOILERPLATE(RXEditionManager, sharedEditionManager)

- (BOOL)_writeSettings {
    NSData* settings_data = [NSPropertyListSerialization dataFromPropertyList:_settings
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                             errorDescription:NULL];
    if (!settings_data)
        return NO;
    
    NSString* settings_path = [[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:@"Edtion Manager.plist"];
    return [settings_data writeToFile:settings_path options:NSAtomicWrite error:NULL];
}

- (id)init  {
    self = [super init];
    if (!self)
        return nil;
    
    editions = [NSMutableDictionary new];
    edition_proxies = [NSMutableArray new];
    
    active_stacks = [NSMutableDictionary new];
    
    _valid_mount_paths_lock = OS_SPINLOCK_INIT;
    _valid_mount_paths = [NSMutableArray new];
    _validated_mount_paths = [NSMutableArray new];
    _waiting_disc_name = nil;
    
    // find the Editions directory
    NSString* editions_directory = [[NSBundle mainBundle] pathForResource:@"Editions" ofType:nil];
    if (!editions_directory)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Riven X could not find the Editions bundle resource directory."
                                     userInfo:nil];
    
    // cache the path to the Patches directory
    _patches_directory = [[editions_directory stringByAppendingPathComponent:@"Patches"] retain];
    
    // get its content
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray* edition_plists;
    NSError* error = nil;
    if ([fm respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)])
        edition_plists = [fm contentsOfDirectoryAtPath:editions_directory error:&error];
    else
        edition_plists = [fm directoryContentsAtPath:editions_directory];
    if (!edition_plists)
        @throw [NSException exceptionWithName:@"RXMissingResourceException"
                                       reason:@"Riven X could not iterate the Editions bundle resource directory."
                                     userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
    
    // iterate over its content
    NSEnumerator* e = [edition_plists objectEnumerator];
    NSString* item;
    while ((item = [e nextObject])) {
        // is it a plist?
        if (![[item pathExtension] isEqualToString:@"plist"])
            continue;
        
        // cache the full path
        NSString* plist_path = [editions_directory stringByAppendingPathComponent:item];
        
        // try to allocate an edition object
        RXEdition* ed = [[RXEdition alloc] initWithDescriptor:[NSDictionary dictionaryWithContentsOfFile:plist_path]];
        if (!ed)
            RXOLog(@"failed to load edition %@", item);
        else {
            [editions setObject:ed forKey:[ed valueForKey:@"key"]];
            [edition_proxies addObject:[ed proxy]];
        }
        [ed release];
    }
    
    // get the location of the local data store
    _local_data_store = [[[[[RXWorld sharedWorld] worldBase] path] stringByAppendingPathComponent:@"Data"] retain];
    
#if defined(DEBUG)
    if (!BZFSDirectoryExists(_local_data_store)) {
        [_local_data_store release];
        _local_data_store = [[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"Data"] retain];
    }
#endif
    
    // check if the local data store exists (it is not required)
    if (!BZFSDirectoryExists(_local_data_store)) {
        [_local_data_store release];
        _local_data_store = nil;
#if defined(DEBUG)
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"no local data store could be found");
#endif
    }
    
    // load edition manager settings
    NSString* settings_path = [[[[RXWorld sharedWorld] worldUserBase] path] stringByAppendingPathComponent:@"Edtion Manager.plist"];
    if (BZFSFileExists(settings_path)) {
        NSData* settings_data = [NSData dataWithContentsOfFile:settings_path options:0 error:&error];
        if (settings_data == nil)
            @throw [NSException exceptionWithName:@"RXIOException"
                                           reason:@"Riven X could not load the existing edition manager settings."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error, NSUnderlyingErrorKey, nil]];
        
        NSString* error_string = nil;
        _settings = [[NSPropertyListSerialization propertyListFromData:settings_data
                                                      mutabilityOption:NSPropertyListMutableContainers
                                                                format:NULL errorDescription:&error_string] retain];
        if (_settings == nil)
            @throw [NSException exceptionWithName:@"RXIOException"
                                           reason:@"Riven X could not load the existing edition manager settings."
                                         userInfo:[NSDictionary dictionaryWithObjectsAndKeys:error_string, @"RXErrorString", nil]];
        [error_string release];
    } else
        _settings = [NSMutableDictionary new];
    
    // if we have an edition selection saved in the settings, try to use it; otherwise, display the edition manager; 
    // we use a performSelector because the world is not done initializing when the edition manager is initialized
    // and we must defer the edition changed notification until the next run loop cycle
    RXEdition* default_edition = [self defaultEdition];
    
    BOOL option_pressed = ((GetCurrentKeyModifiers() & (optionKey | rightOptionKey)) != 0) ? YES : NO;
    if (default_edition && !option_pressed)
        [self performSelectorOnMainThread:@selector(_makeEditionChoiceMemoryCurrent) withObject:nil waitUntilDone:NO];
    else {
        // show the edition manager
//        [self showEditionManagerWindow];
    }
    
    return self;
}

- (void)tearDown {
    if (_torn_down)
        return;
    _torn_down = YES;
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

- (void)dealloc {
    [self tearDown];
    
    [_valid_mount_paths release];
    [_validated_mount_paths release];
    [_waiting_disc_name release];
    
    [_local_data_store release];
    
    [_patches_directory release];
    
    [editions release];
    [edition_proxies release];
    
    [active_stacks release];
    [_extras_archive release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark edition management

- (NSArray*)editionProxies {
    return [[edition_proxies retain] autorelease];
}

- (RXEdition*)editionForKey:(NSString*)editionKey {
    return [[[editions objectForKey:editionKey] retain] autorelease];
}

- (RXEdition*)currentEdition {
    return [[current_edition retain] autorelease];
}

- (RXEdition*)defaultEdition {
    return [editions objectForKey:[_settings objectForKey:@"RXEditionChoiceMemory"]];
}

- (void)setDefaultEdition:(RXEdition*)edition {
    if (edition)
        [_settings setObject:[edition valueForKey:@"key"] forKey:@"RXEditionChoiceMemory"];
    else
        [_settings removeObjectForKey:@"RXEditionChoiceMemory"];
    [self _writeSettings];
}

- (void)resetDefaultEdition {
    [self setDefaultEdition:nil];
}

- (BOOL)makeEditionCurrent:(RXEdition*)edition rememberChoice:(BOOL)remember error:(NSError**)error {
    if ([edition isEqual:current_edition]) {
        // if we're told to remember this choice, do so
        if (remember)
            [self setDefaultEdition:edition];
        return YES;
    }

    // check that this edition can become current
    if (![edition canBecomeCurrent]) {
        if (error) {
            *error = [NSError errorWithDomain:RXErrorDomain code:kRXErrEditionCantBecomeCurrent userInfo:
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       [NSString stringWithFormat:NSLocalizedStringFromTable(@"CANNOT_MAKE_EDITION_CURRENT", @"Editions", @"can't make edition current"), [edition valueForKey:@"name"]], NSLocalizedDescriptionKey,
                       NSLocalizedStringFromTable(@"USE_EDITION_MANAGER_TO_INSTALL", @"Editions", @"use edition manager"), NSLocalizedRecoverySuggestionErrorKey,
                       [NSArray arrayWithObjects:NSLocalizedString(@"INSTALL", @"install"), NSLocalizedString(@"QUIT", @"quit"), nil], NSLocalizedRecoveryOptionsErrorKey,
                       [NSApp delegate], NSRecoveryAttempterErrorKey,
                       nil]];
        }
        return NO;
    }
    
    // if we're told to remember this choice, do so
    if (remember)
        [self setDefaultEdition:edition];
    
    // unload all stacks since they are associated to the current edition
    [active_stacks removeAllObjects];
    
    // unload the current extras archive
    [_extras_archive release];
    _extras_archive = nil;
    
    // change the current edition ivar
    current_edition = edition;
    
    // remove all mount paths from the validated and valid lists because they depend on the current edition
    OSSpinLockLock(&_valid_mount_paths_lock);
    [_validated_mount_paths removeAllObjects];
    [_valid_mount_paths removeAllObjects];
    OSSpinLockUnlock(&_valid_mount_paths_lock);
    
    // try to load the extras archive for the edition
    if (![self extrasArchive:error]) {
        if (error) {
            *error = [NSError errorWithDomain:RXErrorDomain code:kRXErrUnableToLoadExtrasArchive userInfo:
                      [NSDictionary dictionaryWithObjectsAndKeys:
                       [NSString stringWithFormat:NSLocalizedStringFromTable(@"FAILED_LOAD_EXTRAS", @"Editions", "failed to load Extras"), [edition valueForKey:@"name"]], NSLocalizedDescriptionKey,
                       [NSArray arrayWithObjects:NSLocalizedString(@"QUIT", @"quit"), nil], NSLocalizedRecoveryOptionsErrorKey,
                       [NSApp delegate], NSRecoveryAttempterErrorKey,
                       *error, NSUnderlyingErrorKey,
                       nil]];
        }
        return NO;
    }
    
    // post the current edition changed notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXCurrentEditionChangedNotification" object:edition];
    
#if defined(DEBUG)
    RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"made %@ the current edition", edition);
#endif
    return YES;
}

- (void)_makeEditionChoiceMemoryCurrent {
    // NOTE: WILL RUN ON THE MAIN THREAD
    NSError* error;
    if (![self makeEditionCurrent:[self defaultEdition] rememberChoice:YES error:&error]) {
        [self resetDefaultEdition];
        [NSApp presentError:error];
    }
}

#pragma mark -
#pragma mark archive lookup

static NSInteger string_numeric_insensitive_sort(id lhs, id rhs, void* context) {
    return [(NSString*)lhs compare:rhs options:NSCaseInsensitiveSearch | NSNumericSearch];
}

- (NSArray*)_archivesForExpression:(NSString*)regex error:(NSError**)error {
    // if there is no current edition, throw a tantrum
    if (!current_edition)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Riven X tried to get archives for a stack without having a current edition."
                                     userInfo:nil];
    
    // create a predicate to match filenames against the provided regular expression, case insensitive
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"SELF matches[c] %@", regex];
    
    NSMutableArray* matching_paths = [NSMutableArray array];
    NSString* directory;
    NSArray* content;
    
    // first look in the local data store
    if (_local_data_store) {
        directory = _local_data_store;
        content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
        if (content) {
            NSEnumerator* enumerator = [content objectEnumerator];
            NSString* filename;
            while ((filename = [enumerator nextObject]))
                [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
        }
    }
    
    // then look in the edition user data base
    directory = [current_edition valueForKey:@"userDataBase"];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content) {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // then look inside Riven X
    directory = [[NSBundle mainBundle] resourcePath];
    content = [[BZFSContentsOfDirectory(directory, error) filteredArrayUsingPredicate:predicate] sortedArrayUsingFunction:string_numeric_insensitive_sort context:NULL];
    if (content) {
        NSEnumerator* enumerator = [content objectEnumerator];
        NSString* filename;
        while ((filename = [enumerator nextObject]))
            [matching_paths addObject:[directory stringByAppendingPathComponent:filename]];
    }
    
    // load every archive found
    NSMutableArray* archives = [NSMutableArray array];
    NSEnumerator* enumerator = [matching_paths objectEnumerator];
    NSString* archive_path;
    while ((archive_path = [enumerator nextObject])) {
        MHKArchive* archive = [[MHKArchive alloc] initWithPath:archive_path error:error];
        if (archive)
            [archives addObject:archive];
        [archive release];
    }
    
    return archives;
}

- (NSArray*)dataArchivesForStackKey:(NSString*)stack_key error:(NSError**)error {
    return [self _archivesForExpression:[NSString stringWithFormat:@"%C_Data[0-9]?\\.MHK", [stack_key characterAtIndex:0]] error:error];
}

- (NSArray*)soundArchivesForStackKey:(NSString*)stack_key error:(NSError**)error {
    return [self _archivesForExpression:[NSString stringWithFormat:@"%C_Sounds[0-9]?\\.MHK", [stack_key characterAtIndex:0]] error:error];
}

- (MHKArchive*)extrasArchive:(NSError**)error {
    if (!_extras_archive) {
        _extras_archive = [[[self _archivesForExpression:@"Extras\\.MHK" error:error] objectAtIndex:0] retain];
#if defined(DEBUG)
        RXOLog2(kRXLoggingEngine, kRXLoggingLevelDebug, @"loaded Extras archive from %@", [[_extras_archive url] path]);
#endif
    }
    return [[_extras_archive retain] autorelease];
}

- (NSArray*)dataPatchArchivesForStackKey:(NSString*)stack_key error:(NSError**)error {
    // if there is no current edition, throw a tantrum
    if (!current_edition)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Riven X tried to load a patch archive without having a current edition."
                                     userInfo:nil];
    
    NSString* edition_patches_directory = [_patches_directory stringByAppendingPathComponent:[current_edition valueForKey:@"key"]];
    NSDictionary* patch_archives = [current_edition valueForKey:@"patchArchives"];
    
    // if the edition has no patch archives, return an empty array
    if (!patch_archives)
        return [NSArray array];
    
    // get the patch archives for the requested stack; if there are none, return an empty array
    NSDictionary* stack_patch_archives = [patch_archives objectForKey:stack_key];
    if (!stack_patch_archives)
        return [NSArray array];
    
    // get the data patch archives; if there are none, return an empty array
    NSArray* data_patch_archives = [stack_patch_archives objectForKey:@"Data Archives"];
    if (!data_patch_archives)
        return [NSArray array];
    
    // load the data archives
    NSMutableArray* data_archives = [NSMutableArray array];
    
    NSEnumerator* archive_enumerator = [data_patch_archives objectEnumerator];
    NSString* archive_name;
    while ((archive_name = [archive_enumerator nextObject])) {
        NSString* archive_path = BZFSSearchDirectoryForItem(edition_patches_directory, archive_name, YES, error);
        if (!BZFSFileExists(archive_path))
            continue;
        
        MHKArchive* archive = [[MHKArchive alloc] initWithPath:archive_path error:error];
        if (!archive)
            return nil;
        
        [data_archives addObject:archive];
        [archive release];
    }
    
    return data_archives;
}

#pragma mark -
#pragma mark stack management

- (RXStack*)activeStackWithKey:(NSString*)stack_key {
    return [active_stacks objectForKey:stack_key];
}

- (void)_postStackLoadedNotification:(NSString*)stack_key {
    // WARNING: MUST RUN ON THE MAIN THREAD
    if (!pthread_main_np()) {
        [self performSelectorOnMainThread:@selector(_postStackLoadedNotification:) withObject:stack_key waitUntilDone:NO];
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXStackDidLoadNotification" object:stack_key userInfo:nil];
}

- (RXStack*)loadStackWithKey:(NSString*)stack_key {
    RXStack* stack = [self activeStackWithKey:stack_key];
    if (stack)
        return stack;
    
    NSError* error;
        
    // get the stack descriptor from the current edition
    NSDictionary* stack_descriptor = [[[RXEditionManager sharedEditionManager] currentEdition] valueForKeyPath:[NSString stringWithFormat:@"stackDescriptors.%@", stack_key]];
    if (!stack_descriptor || ![stack_descriptor isKindOfClass:[NSDictionary class]])
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Stack descriptor object is nil or of the wrong type."
                                     userInfo:stack_descriptor];
    
    // initialize the stack
    stack = [[RXStack alloc] initWithStackDescriptor:stack_descriptor key:stack_key error:&error];
    if (!stack) {
        error = [NSError errorWithDomain:[error domain] code:[error code] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
            [error localizedDescription], NSLocalizedDescriptionKey,
            NSLocalizedStringFromTable(@"REINSTALL_EDITION", @"Editions", "reinstall edition"), NSLocalizedRecoverySuggestionErrorKey,
            [NSArray arrayWithObjects:NSLocalizedString(@"QUIT", @"quit"), nil], NSLocalizedRecoveryOptionsErrorKey,
            [NSApp delegate], NSRecoveryAttempterErrorKey,
            error, NSUnderlyingErrorKey,
            nil]];
        [NSApp performSelectorOnMainThread:@selector(presentError:) withObject:error waitUntilDone:NO];
        return nil;
    }
        
    // store the new stack in the active stacks dictionary
    [active_stacks setObject:stack forKey:stack_key];
    
    // give up ownership of the new stack
    [stack release];
    
    // post the stack loaded notification on the main thread
    [self _postStackLoadedNotification:stack_key];
    
    // return the stack
    return stack;
}

@end
