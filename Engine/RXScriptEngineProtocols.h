//
//  RXScriptEngineProtocol.h
//  rivenx
//
//  Created by Jean-Francois Roy on 05/05/2008.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//

#import "Base/RXBase.h"

#import "Engine/RXHotspot.h"
#import "Engine/RXCardProtocols.h"


@protocol RXScriptEngineProtocol <NSObject>
- (RXCard*)card;
- (void)setCard:(RXCard*)c;

- (void)openCard;
- (void)startRendering;
- (void)closeCard;

- (NSArray*)activeHotspots;
- (RXHotspot*)activeHotspotWithName:(NSString*)name;
- (void)mouseInsideHotspot:(RXHotspot*)hotspot;
- (void)mouseExitedHotspot:(RXHotspot*)hotspot;
- (void)mouseDownInHotspot:(RXHotspot*)hotspot;
- (void)mouseUpInHotspot:(RXHotspot*)hotspot;

- (void)skipBlockingMovie;
@end


@protocol RXScriptEngineControllerProtocol <RXCardEventsHandlerProtocol, RXCardRendererProtocol>
- (void)setActiveCardWithSimpleDescriptor:(RXSimpleCardDescriptor*)scd waitUntilDone:(BOOL)wait;
- (void)setActiveCardWithStack:(NSString*)stackKey ID:(uint16_t)cardID waitUntilDone:(BOOL)wait;
@end
