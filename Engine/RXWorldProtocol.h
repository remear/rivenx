/*
 *  RXWorldProtocol.h
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 01/10/2005.
 *  Copyright 2005 MacStorm. All rights reserved.
 *
 */

#if !defined(__OBJC__)
#error RXWorldProtocol.h requires Objective-C
#else

#import <sys/cdefs.h>

#import <Cocoa/Cocoa.h>
#import <MHKKit/MHKKit.h>

#import "Engine/RXStack.h"
#import "Rendering/RXRendering.h"
#import "Rendering/Graphics/RXStateCompositor.h"
#import "Engine/RXGameState.h"


@protocol RXWorldProtocol <NSObject>
- (NSThread*)scriptThread;

- (NSDictionary*)extraBitmapsDescriptor;

- (RXStateCompositor*)stateCompositor;
- (void*)audioRenderer;
- (RXRenderState*)cardRenderState;

- (RXGameState*)gameState;

- (id)valueForEngineVariable:(NSString*)path;
- (void)setValue:(id)value forEngineVariable:(NSString*)path;

- (NSCursor*)defaultCursor;
- (NSCursor*)openHandCursor;
- (NSCursor*)invisibleCursor;
- (NSCursor*)cursorForID:(uint16_t)ID;
@end


__BEGIN_DECLS

extern NSObject <RXWorldProtocol>* g_world;

CF_INLINE BOOL RXEngineGetBool(NSString* path) {
    id value = [g_world valueForEngineVariable:path];
    if (!value || ![value isKindOfClass:[NSNumber class]])
        return NO;
    return [value boolValue];
}

CF_INLINE uint32_t RXEngineGetUInt32(NSString* path) {
    id value = [g_world valueForEngineVariable:path];
    if (!value || ![value isKindOfClass:[NSNumber class]])
        return NO;
    return (uint32_t)[value unsignedIntValue];
}

CF_INLINE void RXEngineSetUInt32(NSString* path, uint32_t value) {
    [g_world setValue:[NSNumber numberWithInt:value] forEngineVariable:path];
}

__END_DECLS

#endif // __OBJC__
