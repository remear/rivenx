//
//	RXCardDescriptor.m
//	rivenx
//
//	Created by Jean-Francois Roy on 29/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import "RXCardDescriptor.h"
#import "RXStack.h"

struct _RXCardDescriptorPrimer {
	MHKArchive* archive;
	NSData* data;
};


@interface RXStack (RXCardDescriptor)
- (struct _RXCardDescriptorPrimer)_cardPrimerWithID:(uint16_t)cardResourceID;
@end

@implementation RXStack (RXCardDescriptor)

- (struct _RXCardDescriptorPrimer)_cardPrimerWithID:(uint16_t)cardResourceID {
	NSEnumerator* dataArchivesEnum = [_dataArchives objectEnumerator];
	MHKArchive* archive = nil;
	
	NSData* data = nil;
	while ((archive = [dataArchivesEnum nextObject])) {
		MHKFileHandle* fh = [archive openResourceWithResourceType:@"CARD" ID:cardResourceID];
		if (!fh) continue;
		
		// FIXME: check that file size doesn't overflow size_t
		size_t bufferLength = (size_t)[fh length];
		void* buffer = malloc(bufferLength);
		if (!buffer) continue;
		
		// read the data from the archive
		NSError* error;
		[fh readDataToEndOfFileInBuffer:buffer error:&error];
		if (error) continue;
		
		data = [NSData dataWithBytesNoCopy:buffer length:bufferLength freeWhenDone:YES];
		if (data) break;
	}
	
	struct _RXCardDescriptorPrimer primer = {archive, data};
	return primer;
}

@end


@implementation RXCardDescriptor

+ (id)descriptorWithStack:(RXStack *)stack ID:(uint16_t)cardID {
	return [[[RXCardDescriptor alloc] initWithStack:stack ID:cardID] autorelease];
}

- (id)init {
	[self doesNotRecognizeSelector:_cmd];
	[self release];
	return nil;
}

- (id)initWithStack:(RXStack *)stack ID:(uint16_t)cardID {
	self = [super init];
	if (!self) return nil;
	
	// try to get a primer
	struct _RXCardDescriptorPrimer primer = [stack _cardPrimerWithID:cardID];
	if (primer.data == nil) {
		[self release];
		return nil;
	}
	
	// WARNING: weak reference to the stack and archive
	_parent = stack;
	_ID = cardID;
	
	_archive = primer.archive;
	_data = [primer.data retain];
	
	// FIXME: add methods to query the stack about its name
	_name = [[[NSNumber numberWithUnsignedShort:_ID] stringValue] retain];
	
	return self;
}

- (void)dealloc {
	[_data release];
	[_name release];
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat: @"%@ %03hu", [_parent key], _ID];
}

@end

@implementation RXSimpleCardDescriptor

- (id)initWithStackName:(NSString*)name ID:(uint16_t)ID {
	self = [super init];
	if (!self) return nil;
	
	_parentName = [name copy];
	_ID = ID;
	
	return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
	if (![decoder containsValueForKey:@"parent"]) {
		[self release];
		return nil;
	}
	NSString* parent = [decoder decodeObjectForKey:@"parent"];

	if (![decoder containsValueForKey:@"ID"]) {
		[self release];
		return nil;
	}
	uint16_t ID = (uint16_t)[decoder decodeInt32ForKey:@"ID"];
	
	self = [self initWithStackName:parent ID:ID];
	return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder {
	if (![encoder allowsKeyedCoding]) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"RXCardDescriptor only supports keyed archiving." userInfo:nil];
	
	[encoder encodeObject:_parentName forKey:@"parent"];
	[encoder encodeInt32:_ID forKey:@"ID"];
}

- (void)dealloc {
	[_parentName release];
	[super dealloc];
}

@end