//
//	RXStack.m
//	rivenx
//
//	Created by Jean-Francois Roy on 30/08/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <MHKKit/MHKKit.h>

#import "RXStack.h"
#import "RXCardDescriptor.h"

#import "RXWorldProtocol.h"
#import "RXEditionManager.h"

static NSArray* _loadNAMEResourceWithID(MHKArchive* archive, uint16_t resourceID) {
	NSData* nameData = [archive dataWithResourceType:@"NAME" ID:resourceID];
	if (!nameData) return nil;
	
	uint16_t recordCount = CFSwapInt16BigToHost(*(const uint16_t *)[nameData bytes]);
	NSMutableArray* recordArray = [[NSMutableArray alloc] initWithCapacity:recordCount];
	
	const uint16_t* offsetBase = (uint16_t *)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t));
	const uint8_t* stringBase = (uint8_t *)BUFFER_OFFSET([nameData bytes], sizeof(uint16_t) + (sizeof(uint16_t) * 2 * recordCount));
	
	uint16_t currentRecordIndex = 0;
	for (; currentRecordIndex < recordCount; currentRecordIndex++) {
		uint16_t recordOffset = CFSwapInt16BigToHost(offsetBase[currentRecordIndex]);
		const unsigned char* entryBase = (const unsigned char *)stringBase + recordOffset;
		size_t recordLength = strlen((const char *)entryBase);
		
		// check for leading and closing 0xbd
		if (*entryBase == 0xbd) {
			entryBase++;
			recordLength--;
		}
		
		if (*(entryBase + recordLength - 1) == 0xbd) recordLength--;
		
		NSString* record = [[NSString alloc] initWithBytes:entryBase length:recordLength encoding:NSASCIIStringEncoding];
		[recordArray addObject:record];
		[record release];
	}
	
	return recordArray;
}


@interface RXStack (RXStackPrivate)
- (void)_load;
- (void)_tearDown;
@end

@implementation RXStack

// disable automatic KVC
+ (BOOL)accessInstanceVariablesDirectly {
	return NO;
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithStackDescriptor:(NSDictionary *)descriptor key:(NSString *)key {
	self = [super init];
	if (!self) return nil;
	
	if (pthread_main_np()) {
		[self release];
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"DO NOT INITIALIZE STACK ON MAIN THREAD" userInfo:nil];
	}
	
	// check that we have a descriptor object
	if (!descriptor) {
		[self release];
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Descriptor dictionary cannot be nil." userInfo:nil];
	}
	
	_entryCardID = [[descriptor objectForKey:@"Entry"] unsignedShortValue];
	
	// check that we have a key object
	if (!key) {
		[self release];
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Key string cannot be nil." userInfo:nil];
	}
	_key = [key copy];
	
	// subscribe for notifications that the stack thread has died
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_runThreadWillDie:) name:NSThreadWillExitNotification object:nil];
	
	// allocate the archives arrays
	_dataArchives = [[NSMutableArray alloc] initWithCapacity:2];
	_soundArchives = [[NSMutableArray alloc] initWithCapacity:1];
	
	// get the data archives list
	id dataArchives = [descriptor objectForKey:@"Data Archives"];
	if (!dataArchives) {
		[self release];
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Descriptor dictionary does not contain data archives information." userInfo:nil];
	}
	
	// get the sound archives list
	id soundArchives = [descriptor objectForKey:@"Sound Archives"];
	if (!soundArchives) {
		[self release];
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Descriptor dictionary does not contain sound archives information." userInfo:nil];
	}
	
	// initialize descritors
	_cardCount = 0;
	unsigned int cardDescriptorAlignedSize = 0;
	NSGetSizeAndAlignment(@encode(RXCardDescriptor), NULL, &cardDescriptorAlignedSize);
	
	// get the edition manager
	RXEditionManager* sem = [RXEditionManager sharedEditionManager];
	
	// load all the archives in a try block to release and re-throw
	NSError* error;
	@try {
		// load the data archives
		if ([dataArchives isKindOfClass:[NSString class]]) {
			// only one archive
			MHKArchive* anArchive = [sem dataArchiveWithFilename:dataArchives stackID:_key error:&error];
			if (!anArchive) @throw [NSException exceptionWithName:@"RXMissingArchiveException" reason:[NSString stringWithFormat:@"Failed to open the archive \"%@\".", dataArchives] userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
			[_dataArchives addObject:anArchive];
			
			// card descriptors
			NSArray* resourceDescriptors = [anArchive valueForKey:@"CARD"];
			_cardCount = [resourceDescriptors count];
		} else if ([dataArchives isKindOfClass:[NSArray class]]) {
			// enumerate the archives
			NSEnumerator* archivesEnum = [dataArchives objectEnumerator];
			NSString* anArchiveName = nil;
			while ((anArchiveName = [archivesEnum nextObject])) {
				MHKArchive* anArchive = [sem dataArchiveWithFilename:anArchiveName stackID:_key error:&error];
				if (!anArchive) @throw [NSException exceptionWithName:@"RXMissingArchiveException" reason:[NSString stringWithFormat:@"Failed to open the archive \"%@\".", anArchiveName] userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
				[_dataArchives addObject:anArchive];
				
				// card descriptors
				NSArray* resourceDescriptors = [anArchive valueForKey:@"CARD"];
				_cardCount += [resourceDescriptors count];
			}
		} else @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Data Archives object has an invalid type." userInfo:nil];
		
		// load the sound archives
		if ([soundArchives isKindOfClass:[NSString class]]) {
			MHKArchive* anArchive = [sem soundArchiveWithFilename:soundArchives stackID:_key error:&error];
			if (!anArchive) @throw [NSException exceptionWithName:@"RXMissingArchiveException" reason:[NSString stringWithFormat:@"Failed to open the archive \"%@\".", soundArchives] userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
			[_soundArchives addObject:anArchive];
		} else if ([soundArchives isKindOfClass:[NSArray class]]) {
			NSEnumerator* archivesEnum = [soundArchives objectEnumerator];
			NSString* anArchiveName = nil;
			while ((anArchiveName = [archivesEnum nextObject])) {
				MHKArchive* anArchive = [sem soundArchiveWithFilename:anArchiveName stackID:_key error:&error];
				if (!anArchive) @throw [NSException exceptionWithName:@"RXMissingArchiveException" reason:[NSString stringWithFormat:@"Failed to open the archive \"%@\".", anArchiveName] userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
				[_soundArchives addObject:anArchive];
			}
		} else @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Sound Archives object has an invalid type." userInfo:nil];
	} @catch (NSException* e) {
		RXOLog(@"exception thrown during initialization: %@", e);
		[self release];
		@throw e;
	}
	
	// load me up, baby
	[self _load];
	
	return self;
}

- (void)_load {
	MHKArchive* masterDataArchive = [_dataArchives lastObject];
	
	// global stack data
	_cardNames = _loadNAMEResourceWithID(masterDataArchive, 1);
	_hotspotNames = _loadNAMEResourceWithID(masterDataArchive, 2);
	_externalNames = _loadNAMEResourceWithID(masterDataArchive, 3);
	_varNames = _loadNAMEResourceWithID(masterDataArchive, 4);
	_stackNames = _loadNAMEResourceWithID(masterDataArchive, 5);
	
	// rmap data
	NSDictionary* rmapDescriptor = [[masterDataArchive valueForKey:@"RMAP"] objectAtIndex:0];
	uint16_t remapID = [[rmapDescriptor valueForKey:@"ID"] unsignedShortValue];
	_rmapData = [[masterDataArchive dataWithResourceType:@"RMAP" ID:remapID] retain];
	
#if defined(DEBUG)
	RXOLog(@"stack entry card is %d", _entryCardID);
#endif
}

- (void)_tearDown {
#if defined(DEBUG)
	RXOLog(@"tearing down");
#endif
	
	// no more thread or port notification, and no more run loop observers (causing the run loop to stop)
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	// release a bunch of objects
	[_cardNames release]; _cardNames = nil;
	[_hotspotNames release]; _hotspotNames = nil;
	[_externalNames release]; _externalNames = nil;
	[_varNames release]; _varNames = nil;
	[_stackNames release]; _stackNames = nil;
	[_rmapData release]; _rmapData = nil;
	
	[_soundArchives release]; _soundArchives = nil;
	[_dataArchives release]; _dataArchives = nil;
	
	_cardCount = 0;
}

- (void)dealloc {
#if defined(DEBUG)
	RXOLog(@"deallocating");
#endif
	
	// tear done before we deallocate
	[self _tearDown];
	
	[_key release];
	
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat: @"%@{%@}", [super description], _key];
}

- (NSString *)debugName {
	return _key;
}

#pragma mark -

- (void)_runThreadWillDie:(NSNotification *)notification {
	if ([notification object] == [g_world stackThread]) {
#if defined(DEBUG)
		RXOLog(@"stack thread has exited while I still exist");
#endif
		// tear the stack down
		[self _tearDown];
	}
}

#pragma mark -

- (NSString *)key {
	return _key;
}

- (uint16_t)entryCardID {
	return _entryCardID;
}

#pragma mark -

- (NSString*)cardNameAtIndex:(uint32_t)index {
	return (_cardNames) ? [_cardNames objectAtIndex:index] : nil;
}

- (NSString*)hotspotNameAtIndex:(uint32_t)index {
	return (_hotspotNames) ? [_hotspotNames objectAtIndex:index] : nil;
}

- (NSString*)externalNameAtIndex:(uint32_t)index {
	return (_externalNames) ? [_externalNames objectAtIndex:index] : nil;
}

- (NSString*)varNameAtIndex:(uint32_t)index {
	return (_varNames) ? [_varNames objectAtIndex:index] : nil;
}

- (NSString*)stackNameAtIndex:(uint32_t)index {
	return (_stackNames) ? [_stackNames objectAtIndex:index] : nil;
}

- (uint16_t)cardIDFromRMAPCode:(uint32_t)code {
	uint32_t* rmap_data = (uint32_t*)[_rmapData bytes];
	uint32_t* rmap_end = (uint32_t*)((uint8_t*)[_rmapData bytes] + [_rmapData length]);
	uint16_t card_id = 0;
#if defined(__LITTLE_ENDIAN__)
	code = CFSwapInt32(code);
#endif
	while (*(rmap_data + card_id) != code && (rmap_data + card_id) < rmap_end) card_id++;
	if (rmap_data == rmap_end) return 0;
	return card_id;
}

- (id <MHKAudioDecompression>)audioDecompressorWithID:(uint16_t)soundID {
	id <MHKAudioDecompression> decompressor = nil;
	NSEnumerator* archiveEnum = [_soundArchives objectEnumerator];
	MHKArchive* archive;
	while ((archive = [archiveEnum nextObject])) {
		// try to get the decompressor from the archive...
		decompressor = [archive decompressorWithSoundID:soundID error:NULL];
		if (decompressor) break;
	}
	return decompressor;
}

- (id <MHKAudioDecompression>)audioDecompressorWithDataID:(uint16_t)soundID {
	id <MHKAudioDecompression> decompressor = nil;
	NSEnumerator* archiveEnum = [_dataArchives objectEnumerator];
	MHKArchive* archive;
	while ((archive = [archiveEnum nextObject])) {
		// try to get the decompressor from the archive...
		decompressor = [archive decompressorWithSoundID:soundID error:NULL];
		if (decompressor) break;
	}
	return decompressor;
}

@end