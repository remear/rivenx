/*
 *	RXWorldProtocol.h
 *	rivenx
 *
 *	Created by Jean-Francois Roy on 01/10/2005.
 *	Copyright 2005 MacStorm. All rights reserved.
 *
 */

#import "RXStack.h"
#import "RXRendering.h"
#import "RXStateCompositor.h"
#import "RXGameState.h"


@protocol RXWorldProtocol
- (NSThread*)stackThread;
- (NSThread*)scriptThread;

- (NSArray*)activeStacks;
- (RXStack*)activeStackWithKey:(NSString *)key;

- (void)loadStackWithKey:(NSString*)stackKey waitUntilDone:(BOOL)waitFlag;

- (RXStateCompositor*)stateCompositor;
- (void*)audioRenderer;

- (RXRenderState*)cyanMovieRenderState;
- (RXRenderState*)cardRenderState;
- (RXRenderState*)creditsRenderState;

- (RXGameState*)gameState;

- (NSCursor*)defaultCursor;
- (NSCursor*)cursorForID:(uint16_t)ID;
@end


extern NSObject <RXWorldProtocol>* g_world;

CF_INLINE BOOL RXEngineGetBool(NSString* path) {
	id o = [g_world valueForKeyPath:path];
	if (!o) return NO;
	return [o boolValue];
}
