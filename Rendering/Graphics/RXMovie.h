//
//	RXMovie.h
//	rivenx
//
//	Created by Jean-Francois Roy on 08/09/2005.
//	Copyright 2005 MacStorm. All rights reserved.
//

#import <QuickTime/QuickTime.h>
#import <QTKit/QTKit.h>

#import "RXRendering.h"


@interface RXMovie : NSObject <RXRenderingProtocol> {
	QTMovie* _movie;
	QTVisualContextRef _visualContext;
	
	long _movieHints;
	CGSize _currentSize;
	
	BOOL loop;
	
	GLfloat _coordinates[16];
	CGRect _renderRect;
	
	GLuint _glTexture;
	void* _textureStorage;
	
	CVImageBufferRef _imageBuffer;
	BOOL _invalidImage;
}

- (id)initWithMovie:(Movie)movie disposeWhenDone:(BOOL)disposeWhenDone;
- (id)initWithURL:(NSURL *)movieURL;

- (QTMovie*)movie;

- (void)setExpectedReadAheadFromDisplayLink:(CVDisplayLinkRef)displayLink;

- (void)setWorkingColorSpace:(CGColorSpaceRef)colorspace;
- (void)setOutputColorSpace:(CGColorSpaceRef)colorspace;

- (BOOL)looping;
- (void)setLooping:(BOOL)flag;

- (void)gotoBeginning;

- (CGSize)currentSize;

@end