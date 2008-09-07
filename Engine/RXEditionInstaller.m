//
//  RXEditionInstaller.m
//  rivenx
//
//  Created by Jean-Francois Roy on 08/02/2008.
//  Copyright 2008 MacStorm. All rights reserved.
//

#import "RXEditionInstaller.h"
#import "RXEditionManager.h"

#import "BZFSOperation.h"
#import "BZFSUtilities.h"


@implementation RXEditionInstaller

- (id)initWithEdition:(RXEdition*)ed {
	self = [super init];
	if (!self) return nil;
	
	edition = [ed retain];
	
	progress = -1.0;
	item = nil;
	stage = [NSLocalizedStringFromTable(@"INSTALLER_PREPARING", @"Editions", NULL) retain];
	remainingTime = -1.0;
	
	return self;
}

- (void)dealloc {
	[edition release];
	[item release];
	[stage release];
	
	[super dealloc];
}

- (void)_updateInstallerProgress:(BOOL)determinate {
	[self willChangeValueForKey:@"progress"];
	if (determinate) progress = ((double)_currentDirective / _directiveCount) + (_directiveProgress / _directiveCount);
	else progress = -1.0;
	[self didChangeValueForKey:@"progress"];
}

- (BOOL)_performInstallSystemWide:(BOOL)systemWide fullInstall:(BOOL)full session:(NSModalSession)session error:(NSError**)error {
	// we're one-shot
	if (_didRun) ReturnValueWithError(NO, @"RXErrorDomain", 0, nil, error);
	_didRun = YES;
	
	// destination depends on the install's scope
	NSString* destination;
	if (!systemWide) destination = [edition valueForKey:@"userDataBase"];
	else destination = nil;
	
	// first pass to count the number of directives we have to execute and compute progress-tracking numbers
	_directiveCount = 0;
	
	NSEnumerator* directives = [[edition valueForKeyPath:@"installDirectives"] objectEnumerator];
	NSDictionary* directive;
	while ((directive = [directives nextObject])) {
		// a minimal install is only concerned with required directives
		if (!full && [[directive objectForKey:@"Required"] boolValue] == NO) continue;
		
		// check that we can execute this directive
		SEL directiveSelector = NSSelectorFromString([NSString stringWithFormat:@"_perform%@:destination:modalSession:error:", [directive objectForKey:@"Directive"]]);
		if (![self respondsToSelector:directiveSelector]) {
			RXOLog(@"ERROR: unknown installation directive: %@", [directive objectForKey:@"Directive"]);
			ReturnValueWithError(NO, @"RXErrorDomain", 0, nil, error);
		}
		
		_directiveCount++;
	}
	
	// second pass that actually runs the directives
	_currentDirective = 0;
	directives = [[edition valueForKeyPath:@"installDirectives"] objectEnumerator];
	while ((directive = [directives nextObject])) {
		// a minimal install is only concerned with required directives
		if (!full && [[directive objectForKey:@"Required"] boolValue] == NO) continue;
		
		SEL directiveSelector = NSSelectorFromString([NSString stringWithFormat:@"_perform%@:destination:modalSession:error:", [directive objectForKey:@"Directive"]]);
		NSInvocation* directiveInv = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:directiveSelector]];
		[directiveInv setSelector:directiveSelector];
		[directiveInv setArgument:&directive atIndex:2];
		[directiveInv setArgument:&destination atIndex:3];
		[directiveInv setArgument:&session atIndex:4];
		[directiveInv setArgument:&error atIndex:5];
		[directiveInv invokeWithTarget:self];
		
		BOOL success;
		[directiveInv getReturnValue:&success];
		if (!success) return NO;
		
		_currentDirective++;
		[self _updateInstallerProgress:YES];
	}
	
	return YES;
}

- (BOOL)minimalUserInstallInModalSession:(NSModalSession)session error:(NSError**)error {
	BOOL success = [self _performInstallSystemWide:NO fullInstall:NO session:session error:error];
	if (!success) return NO;
	
	// all done, mark the edition as installed
	[[edition userData] setValue:@"User" forKey:@"Installation Domain"];
	[[edition userData] setValue:@"Minimal" forKey:@"Installation Type"];
	
	// write the edition's user data to disk
	if (![edition writeUserData:error]) return NO;
	return YES;
}

- (BOOL)fullUserInstallInModalSession:(NSModalSession)session error:(NSError**)error {
	BOOL success = [self _performInstallSystemWide:NO fullInstall:YES session:session error:error];
	if (!success) return NO;
	
	// all done, mark the edition as installed
	[[edition userData] setValue:@"User" forKey:@"Installation Domain"];
	[[edition userData] setValue:@"Full" forKey:@"Installation Type"];
	
	// write the edition's user data to disk
	if (![edition writeUserData:error]) return NO;
	return YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([object isKindOfClass:[BZFSOperation class]]) {
		if ([keyPath isEqualToString:@"status"] && [(BZFSOperation*)object stage] == kFSOperationStageRunning) {
			// update the progress
			double bytesCopied = [[[(BZFSOperation*)object status] objectForKey:(NSString*)kFSOperationBytesCompleteKey] unsignedLongLongValue];
			_directiveProgress = (((bytesCopied + _totalBytesCopied) / _totalBytesToCopy) + _discsProcessed) / _discsToProcess;
			[self _updateInstallerProgress:YES];
		}
	}
}

- (BOOL)_performStackCopy:(NSDictionary*)directive destination:(NSString*)destination modalSession:(NSModalSession)session error:(NSError**)error {
	NSDictionary* stackDescriptors = [edition valueForKey:@"stackDescriptors"];
	NSArray* discs = [edition valueForKey:@"discs"];
	NSDictionary* directories = [edition valueForKey:@"directories"];
	
	// step 1: determine which stacks to operate on
	NSArray* stacks = ([directive objectForKey:@"Include"]) ? [NSArray arrayWithObject:[directive objectForKey:@"Include"]] : [stackDescriptors allKeys];
	if ([directive objectForKey:@"Exclude"]) [(NSMutableArray*)(stacks = [[stacks mutableCopy] autorelease]) removeObject:[directive objectForKey:@"Exclude"]];
	
	// step 2: establish a parallel array to the edition's discs mapping disc to stacks (in order to not have the user do mad swapping)
	NSMutableArray* stacksForDiscs = [NSMutableArray array];
	uint32_t discIndex = 0;
	for (; discIndex < [discs count]; discIndex++) {
		NSMutableArray* discStacks = [NSMutableArray array];
		[stacksForDiscs addObject:discStacks];

		NSEnumerator* stackKeyEnum = [stacks objectEnumerator];
		NSString* stackKey;
		while ((stackKey = [stackKeyEnum nextObject])) {
			// get the stack descriptor
			NSDictionary* stackDescriptor = [stackDescriptors objectForKey:stackKey];
			
			// get the stack disc (may not be specified, default to 0)
			uint32_t stackDiscIndex = ([stackDescriptor objectForKey:@"Disc"]) ? [[stackDescriptor objectForKey:@"Disc"] unsignedIntValue] : 0;
			
			// if the directive has a disc override, apply it
			if ([directive objectForKey:@"Disc"]) stackDiscIndex = [[directive objectForKey:@"Disc"] unsignedIntValue];
			
			// if the disc index matched the current disc index, add the stack key to the array of stacks for the current disc
			if (stackDiscIndex == discIndex) [discStacks addObject:stackKey];
		}
	}
	
	// step 3: count the number of discs to process (omitting discs with no stacks to process)
	_discsProcessed = 0;
	NSEnumerator* discStacksEnum = [stacksForDiscs objectEnumerator];
	NSArray* discStacks;
	while ((discStacks = [discStacksEnum nextObject])) if ([discStacks count] > 0) _discsToProcess++;
	
	// step 4: process the stacks of each disc
	
	// update the progress
	_directiveProgress = 0.0;
	[self _updateInstallerProgress:YES];
	
	// process the discs
	discIndex = 0;
	discStacksEnum = [stacksForDiscs objectEnumerator];
	while ((discStacks = [discStacksEnum nextObject])) {
		// ignore the disc if it has no stacks to process
		if ([discStacks count] == 0) {
			discIndex++;
			continue;
		}
		
		// step 4.1: determine the list of files to copy from that disc
		NSMutableArray* files = [NSMutableArray array];
		NSEnumerator* stackKeyEnum = [discStacks objectEnumerator];
		NSString* stackKey;
		while ((stackKey = [stackKeyEnum nextObject])) {
			BOOL doCopy;
			
			// get the stack descriptor
			NSDictionary* stackDescriptor = [stackDescriptors objectForKey:stackKey];
			
			// data archives
			doCopy = ([directive objectForKey:@"Copy Data"]) ? [[directive objectForKey:@"Copy Data"] boolValue] : YES;
			if (doCopy) {
				NSString* directory = ([stackKey isEqualToString:@"aspit"]) ? [directories objectForKey:@"All"] : [directories objectForKey:@"Data"];
				id archives = [stackDescriptor objectForKey:@"Data Archives"];
				if ([archives isKindOfClass:[NSString class]]) [files addObject:[directory stringByAppendingPathComponent:archives]];
				else {
					NSEnumerator* filesEnum = [archives objectEnumerator];
					NSString* file;
					while ((file = [filesEnum nextObject])) [files addObject:[directory stringByAppendingPathComponent:file]];
				}
			}
			
			// sound archives
			doCopy = ([directive objectForKey:@"Copy Sound"]) ? [[directive objectForKey:@"Copy Sound"] boolValue] : YES;
			if (doCopy) {
				NSString* directory = [directories objectForKey:@"Sound"];
				id archives = [stackDescriptor objectForKey:@"Sound Archives"];
				if ([archives isKindOfClass:[NSString class]]) [files addObject:[directory stringByAppendingPathComponent:archives]];
				else {
					NSEnumerator* filesEnum = [archives objectEnumerator];
					NSString* file;
					while ((file = [filesEnum nextObject])) [files addObject:[directory stringByAppendingPathComponent:file]];
				}
			}
		}
		
		// reset the byte counters
		_totalBytesToCopy = 0;
		_totalBytesCopied = 0;
		
		// step 4.2: wait for the disc
		NSString* disc = [discs objectAtIndex:discIndex];
		NSString* mountPath = [[RXEditionManager sharedEditionManager] mountPathForDisc:disc];
		
		// if the disc we need is not mounted, wait for it. if there is no modal session, this will loop until the disc is mounted
		while (!mountPath) {
			// set the UI to indeterminate waiting for disc
			[self _updateInstallerProgress:NO];
			[self setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_INSERT_DISC", @"Editions", NULL), disc] forKey:@"stage"];
			
			mountPath = [[RXEditionManager sharedEditionManager] mountPathForDisc:disc waitingInModalSession:session];
			if (session && [NSApp runModalSession:session] != NSRunContinuesResponse) ReturnValueWithError(NO, @"RXErrorDomain", 0, nil, error);
			if (!mountPath) continue;
			
			// check that every file we need is on that disc, and count the number of bytes to copy at the same time
			[self setValue:NSLocalizedStringFromTable(@"INSTALLER_CHECKING_DISC", @"Editions", NULL) forKey:@"stage"];
			if (session && [NSApp runModalSession:session] != NSRunContinuesResponse) ReturnValueWithError(NO, @"RXErrorDomain", 0, nil, error);
			
			NSEnumerator* fileEnum = [files objectEnumerator];
			NSString* filename;
			while ((filename = [fileEnum nextObject])) {
				NSString* filePath = [mountPath stringByAppendingPathComponent:filename];
				
				if (!BZFSFileExists(filePath)) {
					// this is not the right disc
					[[RXEditionManager sharedEditionManager] ejectMountPath:mountPath];
					mountPath = nil;
					break;
				}
				
				// get the file size
				// FIXME: handle errors
				NSDictionary* attributes = BZFSAttributesOfItemAtPath(filePath, error);
				if (attributes) _totalBytesToCopy += [attributes fileSize];
			}
		}
		
		// step 4.3: copy each file
		
		// update the progress
		_directiveProgress = (double)_discsProcessed / _discsToProcess;
		[self _updateInstallerProgress:YES];
		
		NSEnumerator* fileEnum = [files objectEnumerator];
		NSString* filename;
		while ((filename = [fileEnum nextObject])) {
			NSString* filePath = [mountPath stringByAppendingPathComponent:filename];
			
			[self setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"INSTALLER_FILE_COPY", @"Editions", NULL), [filename lastPathComponent]] forKey:@"stage"];
			
			BZFSOperation* copyOp = [[BZFSOperation alloc] initCopyOperationWithSource:filePath destination:destination];
			[copyOp setAllowOverwriting:YES];
			[copyOp scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode error:error];
			
			[copyOp addObserver:self forKeyPath:@"status" options:0 context:NULL];
			
			if (![copyOp start:error]) {
				[copyOp removeObserver:self forKeyPath:@"status"];
				[copyOp release];
				
				return NO;
			}
			
			while ([copyOp stage] != kFSOperationStageComplete) {
				if (session && [NSApp runModalSession:session] != NSRunContinuesResponse) [copyOp cancel:error];
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
			}
			
			// update the progress
			_totalBytesCopied += [[[copyOp status] objectForKey:(NSString*)kFSOperationBytesCompleteKey] unsignedLongLongValue];
			
			[copyOp removeObserver:self forKeyPath:@"status"];
			[copyOp release];
			
			if (session && [NSApp runModalSession:session] != NSRunContinuesResponse) return NO;
		}
		
		discIndex++;
		_discsToProcess++;
	}
	
	return YES;
}

- (BOOL)_performStackDataCopy:(NSDictionary*)directive destination:(NSString*)destination modalSession:(NSModalSession)session error:(NSError**)error {
	NSMutableDictionary* newDirectives = [directive mutableCopy];
	[newDirectives setObject:[NSNumber numberWithBool:NO] forKey:@"Copy Sound"];
	BOOL r = [self _performStackCopy:newDirectives destination:destination modalSession:session error:error];
	[newDirectives release];
	return r;
}

- (BOOL)_performStackSoundCopy:(NSDictionary*)directive destination:(NSString*)destination modalSession:(NSModalSession)session error:(NSError**)error {
	NSMutableDictionary* newDirectives = [directive mutableCopy];
	[newDirectives setObject:[NSNumber numberWithBool:NO] forKey:@"Copy Data"];
	BOOL r = [self _performStackCopy:newDirectives destination:destination modalSession:session error:error];
	[newDirectives release];
	return r;
}

@end
