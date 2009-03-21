//
//	RXHotspot.h
//	rivenx
//
//	Created by Jean-Francois Roy on 31/05/2006.
//	Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Engine/RXCoreStructures.h"


@interface RXHotspot : NSObject {
	uint16_t _index;
	uint16_t _ID;
	rx_core_rect_t _rect;
	uint16_t _cursor_id;
	NSDictionary* _script;
	
	NSString* _description;
	NSRect _world_frame;

@public
	BOOL enabled;
}

- (id)initWithIndex:(uint16_t)index ID:(uint16_t)ID rect:(rx_core_rect_t)rect cursorID:(uint16_t)cursorID script:(NSDictionary*)script;

- (void)setName:(NSString*)name;

- (rx_core_rect_t)rect;
- (uint16_t)cursorID;
- (NSDictionary*)script;

- (NSRect)worldFrame;

- (void)enable;

@end
