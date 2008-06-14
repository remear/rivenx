//
//	RXCardDescriptor.h
//	rivenx
//
//	Created by Jean-Francois Roy on 29/01/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MHKKit/MHKKit.h>


@class RXStack;

@interface RXCardDescriptor : NSObject {
	RXStack* _parent;
	uint16_t _ID;
	
	MHKArchive* _archive;
	NSData* _data;
	NSString* _name;
}

+ (id)descriptorWithStack:(RXStack *)stack ID:(uint16_t)ID;
- (id)initWithStack:(RXStack *)stack ID:(uint16_t)ID;

- (NSString *)description;

- (RXSimpleCardDescriptor*)simpleDescriptor;

@end

@interface RXSimpleCardDescriptor : NSObject <NSCoding> {
@public
	NSString* _parentName;
	uint16_t _ID;
}

- (id)initWithStackName:(NSString*)name ID:(uint16_t)ID;

@end