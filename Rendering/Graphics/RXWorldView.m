//
//  RXWorldView.m
//  rivenx
//
//  Created by Jean-Francois Roy on 04/09/2005.
//  Copyright 2005-2012 MacStorm. All rights reserved.
//


#import <OpenGL/CGLMacro.h>
#import <OpenGL/CGLRenderers.h>

#import "Rendering/Graphics/RXWorldView.h"

#import "Base/RXThreadUtilities.h"
#import "Application/RXApplicationDelegate.h"
#import "Engine/RXWorldProtocol.h"

#import "Rendering/Graphics/GL/GLShaderProgramManager.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSOpenGL.h>
#import <AppKit/NSWindow.h>


#ifndef kCGLRendererIDMatchingMask
#define kCGLRendererIDMatchingMask   0x00FE7F00
#endif
#ifndef kCGLRendererIntelHD4000ID
#define kCGLRendererIntelHD4000ID    0x00024400
#endif


@interface RXWorldView ()
+ (NSString*)rendererNameForID:(GLint)renderer;

- (void)_handleColorProfileChange:(NSNotification*)notification;

- (void)_initializeCardRendering;
- (void)_updateCardCoordinates;

- (void)_baseOpenGLStateSetup:(CGLContextObj)cgl_ctx;
- (void)_determineGLVersion:(CGLContextObj)cgl_ctx;
- (void)_determineGLFeatures:(CGLContextObj)cgl_ctx;
- (void)_updateTotalVRAM;

- (void)_render:(const CVTimeStamp*)outputTime;
@end


@implementation RXWorldView

static CVReturn rx_render_output_callback(CVDisplayLinkRef displayLink, const CVTimeStamp* inNow, const CVTimeStamp* inOutputTime, CVOptionFlags flagsIn,
    CVOptionFlags* flagsOut, void* ctx)
{
    NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
    [(RXWorldView*)ctx _render:inOutputTime];
    [p release];
    return kCVReturnSuccess;
}

static NSOpenGLPixelFormatAttribute base_window_attribs[] = {
    NSOpenGLPFAWindow,
    NSOpenGLPFADoubleBuffer,
    NSOpenGLPFAColorSize, 24,
    NSOpenGLPFAAlphaSize, 8,
};

static NSString* required_extensions[] = {
    @"GL_APPLE_vertex_array_object",
    @"GL_ARB_texture_rectangle",
    @"GL_ARB_pixel_buffer_object",
    @"GL_EXT_framebuffer_object",
};

+ (BOOL)accessInstanceVariablesDirectly
{
    return NO;
}

+ (NSString*)rendererNameForID:(GLint)renderer
{
    NSString* renderer_name;
    switch (renderer & kCGLRendererIDMatchingMask)
    {
        case kCGLRendererGenericID:
            renderer_name = @"Generic";
            break;
        case kCGLRendererGenericFloatID:
            renderer_name = @"Generic Float";
            break;
        case kCGLRendererAppleSWID:
            renderer_name = @"Apple Software";
            break;

        case kCGLRendererATIRage128ID:
            renderer_name = @"ATI Rage 128";
            break;
        case kCGLRendererATIRadeonID:
            renderer_name = @"ATI Radeon";
            break;
        case kCGLRendererATIRageProID:
            renderer_name = @"ATI Rage Pro";
            break;
        case kCGLRendererATIRadeon8500ID:
            renderer_name = @"ATI Radeon 8500";
            break;
        case kCGLRendererATIRadeon9700ID:
            renderer_name = @"ATI Radeon 9700";
            break;
        case kCGLRendererATIRadeonX1000ID:
            renderer_name = @"ATI Radeon X1000";
            break;
        case kCGLRendererATIRadeonX2000ID:
            renderer_name = @"ATI Radeon X2000";
            break;
        case kCGLRendererATIRadeonX3000ID:
            renderer_name = @"ATI Radeon X3000";
            break;

        case kCGLRendererGeForce2MXID:
            renderer_name = @"NVIDIA GeForce 2MX";
            break;
        case kCGLRendererGeForce3ID:
            renderer_name = @"NVIDIA GeForce 3";
            break;
        case kCGLRendererGeForceFXID:
            renderer_name = @"NVIDIA GeForce FX";
            break;
        case kCGLRendererGeForce8xxxID:
            renderer_name = @"NVIDIA GeForce 8000";
            break;

        case kCGLRendererVTBladeXP2ID:
            renderer_name = @"VT Blade XP2";
            break;

        case kCGLRendererIntel900ID:
            renderer_name = @"Intel 900";
            break;
        case kCGLRendererIntelX3100ID:
            renderer_name = @"Intel X3100";
            break;
        case kCGLRendererIntelHDID:
            renderer_name = @"Intel HD 3000";
            break;
        case kCGLRendererIntelHD4000ID:
            renderer_name = @"Intel HD 4000";
            break;

        case kCGLRendererMesa3DFXID:
            renderer_name = @"Mesa 3DFX";
            break;
        default:
            renderer_name = [NSString stringWithFormat:@"Unknown <%08x>", renderer];
            break;
    }
    
    return renderer_name;
}

- (id)initWithFrame:(NSRect)frame
{
    CGLError cgl_err;
    
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    
    // initialize the global world view reference
    release_assert(g_worldView == nil);
    g_worldView = self;
    
    // prepare the generic "no supported GPU" error
    NSDictionary* error_info = [NSDictionary dictionaryWithObjectsAndKeys:
        NSLocalizedStringFromTable(@"NO_SUPPORTED_GPU", @"Rendering", @"no supported gpu"), NSLocalizedDescriptionKey,
        NSLocalizedStringFromTable(@"UPGRADE_OS_OR_HARDWARE", @"Rendering", @"upgrade Mac OS X or computer or gpu"), NSLocalizedRecoverySuggestionErrorKey,
        [NSArray arrayWithObjects:NSLocalizedString(@"QUIT", @"quit"), nil], NSLocalizedRecoveryOptionsErrorKey,
        [NSApp delegate], NSRecoveryAttempterErrorKey,
        nil];
    NSError* no_supported_gpu_error = [RXError errorWithDomain:RXErrorDomain code:kRXErrFailedToCreatePixelFormat userInfo:error_info];
    
    // process the basic pixel format attributes to a final list of attributes
    NSOpenGLPixelFormatAttribute final_attribs[32] = {0};
    uint32_t pfa_index = sizeof(base_window_attribs) / sizeof(NSOpenGLPixelFormatAttribute) - 1;
    
    // copy the basic attributes
    memcpy(final_attribs, base_window_attribs, sizeof(base_window_attribs));
    
    // allow offline renderers
    final_attribs[++pfa_index] = NSOpenGLPFAAllowOfflineRenderers;
    
    // request a 4x MSAA multisampling buffer by default (if context creation fails, we'll remove those)
    final_attribs[++pfa_index] = NSOpenGLPFASampleBuffers;
    final_attribs[++pfa_index] = 1;
    final_attribs[++pfa_index] = NSOpenGLPFASamples;
    final_attribs[++pfa_index] = 4;
    final_attribs[++pfa_index] = NSOpenGLPFAMultisample;
    final_attribs[++pfa_index] = NSOpenGLPFASampleAlpha;
    
//#define SIMULATE_NO_PF 1
#if SIMULATE_NO_PF
    final_attribs[++pfa_index] = NSOpenGLPFARendererID;
    final_attribs[++pfa_index] = 0xcafebabe;
#endif
    
    // terminate the list of attributes
    final_attribs[++pfa_index] = 0;
    
    // create an NSGL pixel format
    NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:final_attribs];
    if (!format)
    {
        // remove the multisampling buffer attributes
        pfa_index = sizeof(base_window_attribs) / sizeof(NSOpenGLPixelFormatAttribute);
        
#if SIMULATE_NO_PF
        final_attribs[++pfa_index] = NSOpenGLPFARendererID;
        final_attribs[++pfa_index] = 0xcafebabe;
#endif
        
        final_attribs[++pfa_index] = 0;
        
        format = [[NSOpenGLPixelFormat alloc] initWithAttributes:final_attribs];
        if (!format)
        {
            [NSApp presentError:no_supported_gpu_error];
            [self release];
            return nil;
        }
    }
    
    // iterate over the virtual screens to determine the set of virtual screens / renderers we can actually use
    NSMutableSet* viable_renderers = [NSMutableSet set];
    
    NSSet* required_extensions_set = [NSSet setWithObjects:required_extensions count:sizeof(required_extensions) / sizeof(NSString*)];
    NSOpenGLContext* probing_context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    GLint npix = [format numberOfVirtualScreens];
    for (GLint ipix = 0; ipix < npix; ipix++)
    {
        GLint renderer;
        [format getValues:&renderer forAttribute:NSOpenGLPFARendererID forVirtualScreen:ipix];
        
        [probing_context makeCurrentContext];
        [probing_context setCurrentVirtualScreen:ipix];
        
#if DEBUG
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"virtual screen %d is driven by the \"%@\" renderer",
            ipix, [RXWorldView rendererNameForID:renderer]);
#endif

        [self _determineGLFeatures:[probing_context CGLContextObj]];
        
        NSMutableSet* missing_extensions = [[required_extensions_set mutableCopy] autorelease];
        [missing_extensions minusSet:_gl_extensions];
        if ([missing_extensions count] == 0)
        {
//#define FORCE_GENERIC_FLOAT_RENDERER 1
#if FORCE_GENERIC_FLOAT_RENDERER
            if ((renderer & kCGLRendererIDMatchingMask) == kCGLRendererGenericFloatID)
#endif
                [viable_renderers addObject:[NSNumber numberWithInt:renderer]];
        }
    }
    [NSOpenGLContext clearCurrentContext];
    [probing_context release];
    
//#define SIMULATE_NO_VIABLE_RENDERER 1
#if SIMULATE_NO_VIABLE_RENDERER
    [viable_renderers removeAllObjects];
#endif
    
    // if there are no viable renderers, bail out
    if ([viable_renderers count] == 0)
    {
        [format release];
        
        [NSApp presentError:no_supported_gpu_error];
        [self release];
        return nil;
    }
    
    // if there is only one viable renderer, we'll force it in the final pixel format
    else if ([viable_renderers count] == 1)
    {
        final_attribs[pfa_index] = NSOpenGLPFARendererID;
        final_attribs[++pfa_index] = [[viable_renderers anyObject] intValue];
        
        final_attribs[++pfa_index] = 0;
        
        [format release];
        format = [[NSOpenGLPixelFormat alloc] initWithAttributes:final_attribs];
        if (!format)
        {
            [NSApp presentError:no_supported_gpu_error];
            [self release];
            return nil;
        }
    }
    // NOTE: ignoring the case where [viable_renderers count] != [format numberOfVirtualScreens], for now
    
    // set the pixel format on the view
    [self setPixelFormat:format];
    [format release];
    
    // create the render context
    _renderContext = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    if (!_renderContext)
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the render OpenGL context");
        [self release];
        return nil;
    }
    
    // cache the underlying CGL pixel format
    _cglPixelFormat = [format CGLPixelFormatObj];
    
    // set the render context on the view and release it (e.g. transfer ownership to the view)
    [self setOpenGLContext:_renderContext];
    [_renderContext release];
    
    // cache the underlying CGL context
    _renderContextCGL = [_renderContext CGLContextObj];
    release_assert(_renderContextCGL);
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"render context: %p", _renderContextCGL);
    
    // make the rendering context current
    [_renderContext makeCurrentContext];
    
    // initialize GLEW
    glewInit();
    
    // create the state object for the rendering context and store it in the context's client context slot
    NSObject<RXOpenGLStateProtocol>* state = [[RXOpenGLState alloc] initWithContext:_renderContextCGL];
    cgl_err = CGLSetParameter(_renderContextCGL, kCGLCPClientStorage, (const GLint*)&state);
    if (cgl_err != kCGLNoError)
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // create a load context and pair it with the render context
    _loadContext = [[NSOpenGLContext alloc] initWithFormat:format shareContext:_renderContext];
    if (!_loadContext)
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"could not create the resource load OpenGL context");
        [self release];
        return nil;
    }
    
    // cache the underlying CGL context
    _loadContextCGL = [_loadContext CGLContextObj];
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"load context: %p", _loadContextCGL);
    
    // create the state object for the loading context and store it in the context's client context slot
    state = [[RXOpenGLState alloc] initWithContext:_loadContextCGL];
    cgl_err = CGLSetParameter(_loadContextCGL, kCGLCPClientStorage, (const GLint*)&state);
    if (cgl_err != kCGLNoError)
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPClientStorage failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // set a few context options
    GLint param;
    
    // enable vsync on the render context
    param = 1;
    cgl_err = CGLSetParameter(_renderContextCGL, kCGLCPSwapInterval, &param);
    if (cgl_err != kCGLNoError)
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLSetParameter for kCGLCPSwapInterval failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // disable the MT engine as it is a significant performance hit for Riven X; note that we ignore kCGLBadEnumeration errors because of Tiger
    cgl_err = CGLDisable(_renderContextCGL, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError && cgl_err != kCGLBadEnumeration)
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    cgl_err = CGLDisable(_loadContextCGL, kCGLCEMPEngine);
    if (cgl_err != kCGLNoError && cgl_err != kCGLBadEnumeration)
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"CGLEnable for kCGLCEMPEngine failed with error %d: %s",
            cgl_err, CGLErrorString(cgl_err));
        [self release];
        return nil;
    }
    
    // do base state setup
    [self _baseOpenGLStateSetup:_loadContextCGL];
    [self _baseOpenGLStateSetup:_renderContextCGL];
    
    // initialize card rendering
    [self _initializeCardRendering];
    
    // create the CV display link
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &rx_render_output_callback, self);
    
    // color spaces
    _workingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear);
    _sRGBColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    
    // get the default cursor from the world
    _cursor = [[g_world defaultCursor] retain];
    
    // configure the view's autoresizing behavior to resize itself to match its container
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    // initial fade value is 1.0f
    _fadeValue = 1.0f;
    
    return self;
}

- (void)tearDown
{
    if (_tornDown)
        return;
    
    _tornDown = YES;
#if defined(DEBUG)
    RXOLog(@"tearing down");
#endif  
    
    // stop notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // stop the dislay link
    if (_displayLink)
        CVDisplayLinkStop(_displayLink);
}

- (void)dealloc
{
    [self tearDown];
    
    if (_displayLink)
        CVDisplayLinkRelease(_displayLink);
    
    if (_acceleratorService)
        IOObjectRelease(_acceleratorService);
    
    [_loadContext release];
    
    CGColorSpaceRelease(_workingColorSpace);
    CGColorSpaceRelease(_displayColorSpace);
    CGColorSpaceRelease(_sRGBColorSpace);
    
    [_cursor release];
    [_gl_extensions release];
    
    [_fadeInterpolator release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark world view protocol

- (CGLContextObj)renderContext
{
    return _renderContextCGL;
}

- (CGLContextObj)loadContext
{
    return _loadContextCGL;
}

- (CGLPixelFormatObj)cglPixelFormat
{
    return _cglPixelFormat;
}

- (CVDisplayLinkRef)displayLink
{
    return _displayLink;
}

- (CGColorSpaceRef)workingColorSpace
{
    return _workingColorSpace;
}

- (CGColorSpaceRef)displayColorSpace
{
    return _displayColorSpace;
}

- (rx_size_t)viewportSize
{
    return RXSizeMake(_glWidth, _glHeight);
}

- (void)setCardRenderer:(id)renderer
{
    _cardRenderer = RXGetRenderer(renderer);
}

- (NSCursor*)cursor
{
    return _cursor;
}

- (void)setCursor:(NSCursor*)cursor
{
    // NSCursor instances are immutable
    if (cursor == _cursor)
        return;
    
    // the rest of this method must run on the main thread
    if (!pthread_main_np())
    {
        [self performSelectorOnMainThread:@selector(setCursor:) withObject:cursor waitUntilDone:NO];
        return;
    }
    
#if defined(DEBUG) && DEBUG > 1
    if (cursor == [g_world defaultCursor])
        RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"setting cursor to default cursor");
    else if (cursor == [g_world openHandCursor])
        RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"setting cursor to open hand cursor");
    else
        RXOLog2(kRXLoggingEvents, kRXLoggingLevelDebug, @"setting cursor to %@", cursor);
#endif
    
    NSCursor* old = _cursor;
    _cursor = [cursor retain];
    [old release];
    
    [[self window] invalidateCursorRectsForView:self];
}

#pragma mark -
#pragma mark event handling

// we need to forward events to the state compositor, which will forward them to the rendering states

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    return YES;
}

- (void)mouseDown:(NSEvent*)event
{
    [[g_world cardRenderer] mouseDown:event];
}

- (void)mouseUp:(NSEvent*)event
{
    [[g_world cardRenderer] mouseUp:event];
}

- (void)mouseMoved:(NSEvent*)event
{
    [[g_world cardRenderer] mouseMoved:event];
}

- (void)mouseDragged:(NSEvent*)event
{
    [[g_world cardRenderer] mouseDragged:event];
}

- (void)swipeWithEvent:(NSEvent*)event
{
    [[g_world cardRenderer] swipeWithEvent:event];
}

- (void)keyDown:(NSEvent*)event
{
    [[g_world cardRenderer] keyDown:event];
}

- (void)resetCursorRects
{
    [self addCursorRect:[self bounds] cursor:_cursor];
    [_cursor setOnMouseEntered:YES];
}

#pragma mark -
#pragma mark view behavior

- (BOOL)isOpaque
{
    return YES;
}

- (void)_handleColorProfileChange:(NSNotification*)notification
{
    CGDirectDisplayID ddid = CVDisplayLinkGetCurrentCGDisplay(_displayLink);
    ColorSyncProfileRef displayProfile;
    
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"updating display colorspace");
#endif
    
    // ask ColorSync for our current display's profile
    displayProfile = ColorSyncProfileCreateWithDisplayID(ddid);
    if (_displayColorSpace)
        CGColorSpaceRelease(_displayColorSpace);
    
    _displayColorSpace = CGColorSpaceCreateWithPlatformColorSpace(displayProfile);
    CFRelease(displayProfile);
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    
    // remove ourselves from any previous screen or window related notifications
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSWindowDidChangeScreenProfileNotification object:nil];
    
    // get our new window
    NSWindow* w = [self window];
    if (!w)
        return;
    
    // configure our new window
    if ([w respondsToSelector:@selector(setPreferredBackingLocation:)])
        [w setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
    [w useOptimizedDrawing:YES];
    
    // register for color profile changes and trigger one artificially
    [center addObserver:self selector:@selector(_handleColorProfileChange:) name:NSWindowDidChangeScreenProfileNotification object:w];
    [self _handleColorProfileChange:nil];
}

- (void)prepareOpenGL
{
    if (_glInitialized)
        return;
    _glInitialized = YES;
    
    // generate an update so we look at the OpenGL capabilities
    [self update];
    
    // start the CV display link
    CVDisplayLinkStart(_displayLink);
}

extern CGError CGSAcceleratorForDisplayNumber(CGDirectDisplayID display, io_service_t* accelerator, uint32_t* index);

- (void)_updateAcceleratorService
{
    CGLError cglerr;
    CGError cgerr;
    
    if (_acceleratorService)
    {
        IOObjectRelease(_acceleratorService);
        _acceleratorService = 0;
    }
    
    // get the display mask for the current virtual screen
    CGOpenGLDisplayMask display_mask;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFADisplayMask, (GLint*)&display_mask);
    if (cglerr != kCGLNoError)
        return;
    
    // get the corresponding CG display ID
    CGDirectDisplayID display_id = CGOpenGLDisplayMaskToDisplayID(display_mask);
    if (display_id == kCGNullDirectDisplay)
        return;
    
    // use a private CG function to get the accelerator for that display ID
    uint32_t accelerator_index;
    cgerr = CGSAcceleratorForDisplayNumber(display_id, &_acceleratorService, &accelerator_index);
    if (cgerr != kCGErrorSuccess)
        return;
}

- (void)update
{
    [super update];
    
    // the virtual screen has changed, reconfigure the contexts and the display link
    
    CGLLockContext(_renderContextCGL);
    CGLLockContext(_loadContextCGL);

    CGLUpdateContext(_renderContextCGL);
    CGLUpdateContext(_loadContextCGL);
    
    if (_displayLink)
        CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, _renderContextCGL, _cglPixelFormat);
    [_loadContext setCurrentVirtualScreen:[_renderContext currentVirtualScreen]];
    
    GLint renderer;
    CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFARendererID, &renderer);
    
    [self _updateAcceleratorService];
    [self _updateTotalVRAM];
    
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"now using virtual screen %d driven by the \"%@\" renderer; VRAM: %ld MB total, %.2f MB free",
        [_renderContext currentVirtualScreen], [RXWorldView rendererNameForID:renderer], _totalVRAM / 1024 / 1024, [self currentFreeVRAM] / 1024.0 / 1024.0);
    
    renderer &= kCGLRendererIDMatchingMask;
    _intelGraphics = (renderer == kCGLRendererIntel900ID || renderer == kCGLRendererIntelX3100ID) ? YES : NO;
    
    // determine OpenGL version and features
    [self _determineGLFeatures:_renderContextCGL];
    
    // FIXME: determine if we need to fallback to software and do so here; this may not be required since we allow fallback in the pixel format
    
    CGLUnlockContext(_loadContextCGL);
    CGLUnlockContext(_renderContextCGL);
}

- (void)reshape
{
    [super reshape];

    if (!_glInitialized || _tornDown)
        return;

    GLint viewportLeft, viewportBottom;
    NSRect glRect;
    
    // calculate the pixel-aligned rectangle in which OpenGL will render. convertRect converts to/from window coordinates when the view argument is nil
    glRect.size = NSIntegralRect([self convertRect:[self bounds] toView:nil]).size;
    glRect.origin.x = ([self bounds].size.width - glRect.size.width) / 2.0;
    glRect.origin.y = ([self bounds].size.height - glRect.size.height) / 2.0;
    
    // compute the viewport origin
    viewportLeft = glRect.origin.x > 0 ? -glRect.origin.x : 0;
    viewportBottom = glRect.origin.y > 0 ? -glRect.origin.y : 0;
    
    _glWidth = glRect.size.width;
    _glHeight = glRect.size.height;
    
    // use the render context because it's the one that matters for screen output
    CGLContextObj cgl_ctx = _renderContextCGL;
    CGLLockContext(cgl_ctx);
    
    // set the OpenGL viewport
    glViewport(viewportLeft, viewportBottom, _glWidth, _glHeight);
    
    // set up our coordinate system with lower-left at (0, 0) and upper-right at (_glWidth, _glHeight)
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0.0, _glWidth, 0.0, _glHeight, 0.0, 1.0);
    
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glReportError();
    
    // update the card coordinates
    [self _updateCardCoordinates];
    
    // if we'll be applying scaling, switch the MAG filter on the card texture to linear
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _cardTexture);
    NSRect scale_rect = RXRenderScaleRect();
    if (scale_rect.size.width != 1.0f || scale_rect.size.height != 1.0f)
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    else
        glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glReportError();
    
    // let others know that the surface has changed size
#if defined(DEBUG)
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"sending RXOpenGLDidReshapeNotification notification");
#endif
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RXOpenGLDidReshapeNotification" object:self];
    
    CGLUnlockContext(cgl_ctx);
}

#pragma mark -
#pragma mark OpenGL initialization

- (void)_initializeCardRendering
{
    CGLContextObj cgl_ctx = _renderContextCGL;
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    glGenFramebuffersEXT(1, &_cardFBO);
    glGenTextures(1, &_cardTexture);
    
    // bind the texture
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _cardTexture); glReportError();
    
    // texture parameters
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glReportError();
    
    // disable client storage because it's incompatible with allocating texture space with NULL (which is what we want for FBO color attachement textures)
    GLenum client_storage = [gl_state setUnpackClientStorage:GL_FALSE];
    
    // allocate memory for the texture
    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_RGBA8, kRXCardViewportSize.width, kRXCardViewportSize.height, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);
    glReportError();
    
    // color0 texture attach
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _cardFBO); glReportError();
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, _cardTexture, 0); glReportError();
        
    // completeness check
    GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
    if (status != GL_FRAMEBUFFER_COMPLETE_EXT)
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelError, @"card FBO not complete, status 0x%04x\n", (unsigned int)status);
    
    // one VBO for all our vertex attribs
    glGenBuffers(1, &_attribsVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _attribsVBO); glReportError();
    if (GLEW_APPLE_flush_buffer_range)
        glBufferParameteriAPPLE(GL_ARRAY_BUFFER, GL_BUFFER_FLUSHING_UNMAP_APPLE, GL_FALSE);
    glBufferData(GL_ARRAY_BUFFER, 32 * sizeof(GLfloat), NULL, GL_STATIC_DRAW); glReportError();
    
    // create the card VAO
    glGenVertexArraysAPPLE(1, &_cardVAO); glReportError();
    [gl_state bindVertexArrayObject:_cardVAO];
    glBindBuffer(GL_ARRAY_BUFFER, _attribsVBO); glReportError();
    
    // configure the VAs
    glEnableVertexAttribArray(RX_ATTRIB_POSITION); glReportError();
    glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), NULL); glReportError();
    
    glEnableVertexAttribArray(RX_ATTRIB_TEXCOORD0); glReportError();
    glVertexAttribPointer(RX_ATTRIB_TEXCOORD0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 2 * sizeof(GLfloat))); glReportError();
    
    // create the fade VAO
    glGenVertexArraysAPPLE(1, &_fadeLayerVAO); glReportError();
    [gl_state bindVertexArrayObject:_fadeLayerVAO];
    glBindBuffer(GL_ARRAY_BUFFER, _attribsVBO); glReportError();
    
    // configure the VAs
    glEnableVertexAttribArray(RX_ATTRIB_POSITION); glReportError();
    glVertexAttribPointer(RX_ATTRIB_POSITION, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat), BUFFER_OFFSET(NULL, 16 * sizeof(GLfloat))); glReportError();
    
    // get a standard card program
    _cardProgram = [[GLShaderProgramManager sharedManager]
                    standardProgramWithFragmentShaderName:@"card"
                    extraSources:nil
                    epilogueIndex:0
                    context:cgl_ctx
                    error:NULL];
    release_assert(_cardProgram);
    
    glUseProgram(_cardProgram); glReportError();
    
    GLint uniform_loc = glGetUniformLocation(_cardProgram, "destination_card"); glReportError();
    release_assert(uniform_loc != -1);
    glUniform1i(uniform_loc, 0); glReportError();
    
    uniform_loc = glGetUniformLocation(_cardProgram, "modulate_color"); glReportError();
    release_assert(uniform_loc != -1);
    glUniform4f(uniform_loc, 1.f, 1.f, 1.f, 1.f); glReportError();
    
    // get the solid color program
    NSDictionary* bindings = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:RX_ATTRIB_POSITION], @"position",
        nil];
    _solidColorProgram = [[GLShaderProgramManager sharedManager] programWithName:@"solidcolor" attributeBindings:bindings context:cgl_ctx error:NULL];
    release_assert(_solidColorProgram);
    
    glUseProgram(_solidColorProgram); glReportError();
    
    _solidColorLocation = glGetUniformLocation(_solidColorProgram, "color"); glReportError();
    release_assert(_solidColorLocation != -1);
    
    // restore state
    glUseProgram(0);
    [gl_state bindVertexArrayObject:0];
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
    [gl_state setUnpackClientStorage:client_storage];
    glReportError();
}

- (void)_updateCardCoordinates
{
    CGLContextObj cgl_ctx = _renderContextCGL;
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    [gl_state bindVertexArrayObject:_cardVAO];
    glBindBuffer(GL_ARRAY_BUFFER, _attribsVBO);
    glReportError();
    
    struct _attribs {
        GLfloat pos[2];
        GLfloat tex[2];
    };
    release_assert(sizeof(struct _attribs) == 4 * sizeof(GLfloat));
    struct _attribs* attribs = (struct _attribs*)glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY); glReportError();
    release_assert(attribs);
    
    // card
    rx_rect_t contentRect = RXEffectiveRendererFrame();
    
    attribs[0].pos[0] = contentRect.origin.x;                               attribs[0].pos[1] = contentRect.origin.y;
    attribs[0].tex[0] = 0.0f;                                               attribs[0].tex[1] = 0.0f;
    
    attribs[1].pos[0] = contentRect.origin.x + contentRect.size.width;      attribs[1].pos[1] = contentRect.origin.y;
    attribs[1].tex[0] = (GLfloat)kRXCardViewportSize.width;                 attribs[1].tex[1] = 0.0f;
    
    attribs[2].pos[0] = contentRect.origin.x;                               attribs[2].pos[1] = contentRect.origin.y + contentRect.size.height;
    attribs[2].tex[0] = 0.0f;                                               attribs[2].tex[1] = (GLfloat)kRXCardViewportSize.height;
    
    attribs[3].pos[0] = contentRect.origin.x + contentRect.size.width;      attribs[3].pos[1] = contentRect.origin.y + contentRect.size.height;
    attribs[3].tex[0] = (GLfloat)kRXCardViewportSize.width;                 attribs[3].tex[1] = (GLfloat)kRXCardViewportSize.height;
    
    // whole screen
    attribs[4].pos[0] = 0.0f;                                               attribs[4].pos[1] = 0.0f;
    attribs[4].tex[0] = 0.0f;                                               attribs[4].tex[1] = 0.0f;
    
    attribs[5].pos[0] = _glWidth;                                           attribs[5].pos[1] = 0.0f;
    attribs[5].tex[0] = _glWidth;                                           attribs[5].tex[1] = 0.0f;
    
    attribs[6].pos[0] = 0.0f;                                               attribs[6].pos[1] = _glHeight;
    attribs[6].tex[0] = 0.0f;                                               attribs[6].tex[1] = _glHeight;
    
    attribs[7].pos[0] = _glWidth;                                           attribs[7].pos[1] = _glHeight;
    attribs[7].tex[0] = _glWidth;                                           attribs[7].tex[1] = _glHeight;
    
    if (GLEW_APPLE_flush_buffer_range)
        glFlushMappedBufferRangeAPPLE(GL_ARRAY_BUFFER, 0, 32 * sizeof(GLfloat));
    glUnmapBuffer(GL_ARRAY_BUFFER);
    glReportError();
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    [gl_state bindVertexArrayObject:0];
}

- (void)_baseOpenGLStateSetup:(CGLContextObj)cgl_ctx
{
    // set background color to black
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    
    // disable most features that we don't need
    glDisable(GL_BLEND);
    glDisable(GL_CULL_FACE);
    glDisable(GL_DITHER);
    glDisable(GL_LIGHTING);
    glDisable(GL_ALPHA_TEST);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    if (GLEW_ARB_multisample)
        glDisable(GL_MULTISAMPLE_ARB);
    
    // pixel store state
    [RXGetContextState(cgl_ctx) setUnpackClientStorage:GL_TRUE];
    
    // framebuffer masks
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glDepthMask(GL_FALSE);
    glStencilMask(GL_FALSE);
    
    // hints
    glHint(GL_POINT_SMOOTH_HINT, GL_NICEST);
    glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);
    glHint(GL_POLYGON_SMOOTH_HINT, GL_NICEST);
    glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
    glHint(GL_FOG_HINT, GL_NICEST);
    if (GLEW_APPLE_flush_buffer_range)
        glHint(GL_TRANSFORM_HINT_APPLE, GL_NICEST);
    
    glReportError();
}

#pragma mark -
#pragma mark capabilities

- (void)_determineGLVersion:(CGLContextObj)cgl_ctx
{
/*
       The GL_VERSION string begins with a version number.  The version number uses one of these forms:

       major_number.minor_number
       major_number.minor_number.release_number

       Vendor-specific  information  may  follow  the version number. Its  depends on the implementation, but a space
       always separates the version number and the vendor-specific information.
*/
    const GLubyte* glVersionString = glGetString(GL_VERSION); glReportError();
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"GL_VERSION: %s", glVersionString);
    
    GLubyte* minorVersionString;
    _glMajorVersion = (GLuint)strtol((const char*)glVersionString, (char**)&minorVersionString, 10);
    _glMinorVersion = (GLuint)strtol((const char*)minorVersionString + 1, NULL, 10);
    
    // GLSL is somewhat more complicated than mere extensions
    if (_glMajorVersion == 1)
    {
        if ([_gl_extensions containsObject:@"GL_ARB_shader_objects"] &&
            [_gl_extensions containsObject:@"GL_ARB_vertex_shader"] &&
            [_gl_extensions containsObject:@"GL_ARB_fragment_shader"])
        {
            if ([_gl_extensions containsObject:@"GL_ARB_shading_language_110"])
            {
                _glslMajorVersion = 1;
                _glslMinorVersion = 1;
            }
            else if ([_gl_extensions containsObject:@"GL_ARB_shading_language_100"])
            {
                _glslMajorVersion = 1;
                _glslMinorVersion = 0;
            }
        }
        else
        {
            _glslMajorVersion = 0;
            _glslMinorVersion = 0;
        }
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"Computed GLSL version: %u.%u", _glslMajorVersion, _glslMinorVersion);
    }
    else if (_glMajorVersion == 2)
    {
/*
The GL_VERSION and GL_SHADING_LANGUAGE_VERSION strings begin with a version number. The version number uses one of these forms:

major_number.minor_number major_number.minor_number.release_number
*/      
        const GLubyte* glslVersionString = glGetString(GL_SHADING_LANGUAGE_VERSION); glReportError();
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"GL_SHADING_LANGUAGE_VERSION: %s", glVersionString);
        
        GLubyte* minorVersionString;
        _glslMajorVersion = (GLuint)strtol((const char*)glslVersionString, (char**)&minorVersionString, 10);
        _glslMinorVersion = (GLuint)strtol((const char*)minorVersionString + 1, NULL, 10);
    }
    else
    {
        RXOLog2(kRXLoggingGraphics, kRXLoggingLevelDebug, @"unsupported OpenGL major version");
    }
}

- (void)_determineGLFeatures:(CGLContextObj)cgl_ctx
{
    NSString* extensions = [[NSString alloc] initWithCString:(const char*)glGetString(GL_EXTENSIONS) encoding:NSASCIIStringEncoding];
    [_gl_extensions release];
    _gl_extensions = [[NSSet alloc] initWithArray:[extensions componentsSeparatedByString:@" "]];
    [extensions release];

    [self _determineGLVersion:cgl_ctx];

    NSMutableString* features_message = [[NSMutableString alloc] initWithString:@"supported OpenGL features:\n"];
    if ([_gl_extensions containsObject:@"GL_ARB_texture_rectangle"])
        [features_message appendString:@"    texture rectangle (ARB)\n"];
    if ([_gl_extensions containsObject:@"GL_EXT_framebuffer_object"])
        [features_message appendString:@"    framebuffer objects (EXT)\n"];
    if ([_gl_extensions containsObject:@"GL_ARB_pixel_buffer_object"])
        [features_message appendString:@"    pixel buffer objects (ARB)\n"];
    if ([_gl_extensions containsObject:@"GL_APPLE_vertex_array_object"])
        [features_message appendString:@"    vertex array objects (APPLE)\n"];
    if ([_gl_extensions containsObject:@"GL_APPLE_flush_buffer_range"])
        [features_message appendString:@"    flush buffer range (APPLE)\n"];
    RXOLog2(kRXLoggingGraphics, kRXLoggingLevelMessage, @"%@", features_message);
    [features_message release];
}

- (void)_updateTotalVRAM
{
    CGLError cglerr;
    
    // get the display mask for the current virtual screen
    CGOpenGLDisplayMask display_mask;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFADisplayMask, (GLint*)&display_mask);
    if (cglerr != kCGLNoError)
    {
        _totalVRAM = 0;
        return;
    }
    
    // get the renderer ID for the current virtual screen
    GLint renderer;
    cglerr = CGLDescribePixelFormat(_cglPixelFormat, [_renderContext currentVirtualScreen], kCGLPFARendererID, &renderer);
    if (cglerr != kCGLNoError)
    {
        _totalVRAM = 0;
        return;
    }
    
    // get the renderer info object for the display mask
    CGLRendererInfoObj renderer_info;
    GLint renderer_count;
    cglerr = CGLQueryRendererInfo(display_mask, &renderer_info, &renderer_count);
    if (cglerr != kCGLNoError)
    {
        _totalVRAM = 0;
        return;
    }
    
    // find the renderer index for the current renderer
    GLint renderer_index = 0;
    if (renderer_count > 1)
    {
        for (; renderer_index < renderer_count; renderer_index++)
        {
            GLint renderer_id;
            cglerr = CGLDescribeRenderer(renderer_info, 0, kCGLRPRendererID, &renderer_id);
            if (cglerr != kCGLNoError)
            {
                CGLDestroyRendererInfo(renderer_info);
                _totalVRAM = 0;
                return;
            }
            
            if ((renderer_id & kCGLRendererIDMatchingMask) == (renderer & kCGLRendererIDMatchingMask))
                break;
        }
    }
    
    if (renderer_index == renderer_count)
    {
        CGLDestroyRendererInfo(renderer_info);
        _totalVRAM = 0;
        return;
    }

    GLint total_vram;
    cglerr = CGLDescribeRenderer(renderer_info, renderer_index, kCGLRPVideoMemory, &total_vram);
    if (cglerr != kCGLNoError)
    {
        _totalVRAM = 0;
        return;
    }
    CGLDestroyRendererInfo(renderer_info);
    
    _totalVRAM = total_vram;
}

- (ssize_t)currentFreeVRAM
{
    if (!_acceleratorService)
        return 0;
    
    // get the performance statistics ditionary out of the accelerator service
    CFDictionaryRef perf_stats = IORegistryEntryCreateCFProperty(_acceleratorService, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
    if (!perf_stats)
        return 0;
    
    // look for a number of keys (this is mostly reverse engineering and best-guess effort)
    CFNumberRef free_vram_number = NULL;
    ssize_t free_vram;
    BOOL free_number = NO;

    free_vram_number = CFDictionaryGetValue(perf_stats, CFSTR("vramFreeBytes"));
    if (!free_vram_number)
    {
        free_vram_number = CFDictionaryGetValue(perf_stats, CFSTR("vramUsedBytes"));
        if (free_vram_number)
        {
            CFNumberGetValue(free_vram_number, kCFNumberLongType, &free_vram);
            free_vram_number = NULL;
            
            if (_totalVRAM != -1)
            {
                free_vram = _totalVRAM - free_vram;
                free_vram_number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &free_vram);
                free_number = YES;
            }
        }
    }

    // if we did not find or compute a free VRAM number, return an error
    if (!free_vram_number)
    {
        CFRelease(perf_stats);
        return -1;
    }
    
    // get its value out
    CFNumberGetValue(free_vram_number, kCFNumberLongType, &free_vram);
    if (free_number)
        CFRelease(free_vram_number);
    
    // we're done with the perf stats
    CFRelease(perf_stats);
    
    return free_vram;
}

#pragma mark -
#pragma mark rendering

- (void)fadeOutWithDuration:(NSTimeInterval)duration completionDelegate:(id)completionDelegate selector:(SEL)completionSel
{
    float start = (_fadeInterpolator) ? [_fadeInterpolator value] : 0.0f;
    RXAnimation* animation = [[RXCannedAnimation alloc] initWithDuration:duration];
    
    [_fadeInterpolator release];
    _fadeInterpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:start end:1.0f];
    [animation release];
    
    if (_fadeCompletionDelegate)
        [_fadeCompletionDelegate performSelector:_fadeCompletionSel];
    
    _fadeCompletionDelegate = completionDelegate;
    _fadeCompletionSel = completionSel;
    
    [animation startNow];
}

- (void)fadeInWithDuration:(NSTimeInterval)duration completionDelegate:(id)completionDelegate selector:(SEL)completionSel
{
    float start = (_fadeInterpolator) ? [_fadeInterpolator value] : 1.0f;
    RXAnimation* animation = [[RXCannedAnimation alloc] initWithDuration:duration];
    
    [_fadeInterpolator release];
    _fadeInterpolator = [[RXLinearInterpolator alloc] initWithAnimation:animation start:start end:0.0f];
    [animation release];
    
    if (_fadeCompletionDelegate)
        [_fadeCompletionDelegate performSelector:_fadeCompletionSel];
    
    _fadeCompletionDelegate = completionDelegate;
    _fadeCompletionSel = completionSel;
    
    [animation startNow];
}

- (void)_handleFadeCompletion:(id<RXInterpolator>)interpolator
{
    id completionDelegate = _fadeCompletionDelegate;
    SEL completionSel = _fadeCompletionSel;
    
    _fadeCompletionDelegate = nil;
    _fadeCompletionSel = nil;
    [interpolator release];
    
    if (completionDelegate)
        [completionDelegate performSelector:completionSel];
}

- (void)_render:(const CVTimeStamp*)outputTime
{
    if (_tornDown)
        return;
    
    CGLContextObj cgl_ctx = _renderContextCGL;
    CGLSetCurrentContext(cgl_ctx);
    CGLLockContext(cgl_ctx);
    
    NSObject<RXOpenGLStateProtocol>* gl_state = RXGetContextState(cgl_ctx);
    
    // clear to black
    glClear(GL_COLOR_BUFFER_BIT);
    
    if (_cardRenderer.target)
    {
        // bind the card FBO, clear the color buffer and call down to the card renderer
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _cardFBO);
        glClear(GL_COLOR_BUFFER_BIT); glReportError();
        _cardRenderer.render.imp(_cardRenderer.target, _cardRenderer.render.sel, outputTime, cgl_ctx, _cardFBO);
        
        // bind the window surface FBO
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
        
        glUseProgram(_cardProgram);
        [gl_state bindVertexArrayObject:_cardVAO];
        
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _cardTexture);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); glReportError();
        
        glUseProgram(0);
        [gl_state bindVertexArrayObject:0];
        
        // call down to the card renderer again, this time to perform rendering into the system framebuffer
        _cardRenderer.renderInMainRT.imp(_cardRenderer.target, _cardRenderer.render.sel, cgl_ctx);
        
        // if we're running a fade animation, draw a suitably opaque black quad on top of everything
        if (_fadeInterpolator || _fadeValue < 1.0f)
        {
            if (_fadeInterpolator)
                _fadeValue = [_fadeInterpolator value];
            
            glUseProgram(_solidColorProgram);
            glUniform4f(_solidColorLocation, 0.0f, 0.0f, 0.0f, _fadeValue);
            
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glBlendEquationSeparate(GL_FUNC_ADD, GL_FUNC_ADD);
            glEnable(GL_BLEND);
            
            [gl_state bindVertexArrayObject:_fadeLayerVAO];
            
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); glReportError();
            
            glDisable(GL_BLEND);
            glUseProgram(0);
            [gl_state bindVertexArrayObject:0];
            
            if ([_fadeInterpolator isDone])
            {
                id<RXInterpolator> interpolator = _fadeInterpolator;
                _fadeInterpolator = nil;
                [self performSelectorOnMainThread:@selector(_handleFadeCompletion:) withObject:interpolator waitUntilDone:NO];
            }
        }
    }
    
    // glFlush and swap the front and back buffers
    CGLFlushDrawable(cgl_ctx); glReportError();
    
    // finally call down to the card renderer one last time to let it take post-flush actions
    if (_cardRenderer.target)
        _cardRenderer.flush.imp(_cardRenderer.target, _cardRenderer.flush.sel, outputTime);
    
    CGLUnlockContext(cgl_ctx);
}

- (void)drawRect:(NSRect)rect
{
    CVTimeStamp ts;
    CVDisplayLinkGetCurrentTime(_displayLink, &ts);
    
    [self _render:&ts];
}

@end
