/*

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

*/
module derelict.opengl.glx;

private import derelict.util.system;

static if( Derelict_OS_Posix && !Derelict_OS_Mac ) {
    private {
        import std.string;

        import derelict.util.loader;
        import derelict.util.xtypes;
        import derelict.opengl.types;
    }

    enum {
        GLX_USE_GL = 1,
        GLX_BUFFER_SIZE = 2,
        GLX_LEVEL = 3,
        GLX_RGBA = 4,
        GLX_DOUBLEBUFFER = 5,
        GLX_STEREO = 6,
        GLX_AUX_BUFFERS = 7,
        GLX_RED_SIZE = 8,
        GLX_GREEN_SIZE = 9,
        GLX_BLUE_SIZE = 10,
        GLX_ALPHA_SIZE = 11,
        GLX_DEPTH_SIZE = 12,
        GLX_STENCIL_SIZE = 13,
        GLX_ACCUM_RED_SIZE = 14,
        GLX_ACCUM_GREEN_SIZE = 15,
        GLX_ACCUM_BLUE_SIZE = 16,
        GLX_ACCUM_ALPHA_SIZE = 17,
        GLX_BAD_SCREEN = 1,
        GLX_BAD_ATTRIBUTE = 2,
        GLX_NO_EXTENSION = 3,
        GLX_BAD_VISUAL = 4,
        GLX_BAD_CONTEXT = 5,
        GLX_BAD_VALUE = 6,
        GLX_BAD_ENUM = 7,
        GLX_CONFIG_CAVEAT = 0x20,
        GLX_DONT_CARE = 0xFFFFFFFF,
        GLX_X_VISUAL_TYPE = 0x22,
        GLX_TRANSPARENT_TYPE = 0x23,
        GLX_TRANSPARENT_INDEX_VALUE = 0x24,
        GLX_TRANSPARENT_RED_VALUE = 0x25,
        GLX_TRANSPARENT_GREEN_VALUE = 0x26,
        GLX_TRANSPARENT_BLUE_VALUE = 0x27,
        GLX_TRANSPARENT_ALPHA_VALUE = 0x28,
        GLX_WINDOW_BIT = 0x00000001,
        GLX_PIXMAP_BIT = 0x00000002,
        GLX_PBUFFER_BIT = 0x00000004,
        GLX_AUX_BUFFERS_BIT = 0x00000010,
        GLX_FRONT_LEFT_BUFFER_BIT = 0x00000001,
        GLX_FRONT_RIGHT_BUFFER_BIT = 0x00000002,
        GLX_BACK_LEFT_BUFFER_BIT = 0x00000004,
        GLX_BACK_RIGHT_BUFFER_BIT = 0x00000008,
        GLX_DEPTH_BUFFER_BIT = 0x00000020,
        GLX_STENCIL_BUFFER_BIT = 0x00000040,
        GLX_ACCUM_BUFFER_BIT = 0x00000080,
        GLX_NONE = 0x8000,
        GLX_SLOW_CONFIG = 0x8001,
        GLX_TRUE_COLOR = 0x8002,
        GLX_DIRECT_COLOR = 0x8003,
        GLX_PSEUDO_COLOR = 0x8004,
        GLX_STATIC_COLOR = 0x8005,
        GLX_GRAY_SCALE = 0x8006,
        GLX_STATIC_GRAY = 0x8007,
        GLX_TRANSPARENT_RGB = 0x8008,
        GLX_TRANSPARENT_INDEX = 0x8009,
        GLX_VISUAL_ID = 0x800B,
        GLX_SCREEN = 0x800C,
        GLX_NON_CONFORMANT_CONFIG = 0x800D,
        GLX_DRAWABLE_TYPE = 0x8010,
        GLX_RENDER_TYPE = 0x8011,
        GLX_X_RENDERABLE = 0x8012,
        GLX_FBCONFIG_ID = 0x8013,
        GLX_RGBA_TYPE = 0x8014,
        GLX_COLOR_INDEX_TYPE = 0x8015,
        GLX_MAX_PBUFFER_WIDTH = 0x8016,
        GLX_MAX_PBUFFER_HEIGHT = 0x8017,
        GLX_MAX_PBUFFER_PIXELS = 0x8018,
        GLX_PRESERVED_CONTENTS = 0x801B,
        GLX_LARGEST_PBUFFER = 0x801C,
        GLX_WIDTH = 0x801D,
        GLX_HEIGHT = 0x801E,
        GLX_EVENT_MASK = 0x801F,
        GLX_DAMAGED = 0x8020,
        GLX_SAVED = 0x8021,
        GLX_WINDOW = 0x8022,
        GLX_PBUFFER = 0x8023,
        GLX_PBUFFER_HEIGHT = 0x8040,
        GLX_PBUFFER_WIDTH = 0x8041,
        GLX_RGBA_BIT = 0x00000001,
        GLX_COLOR_INDEX_BIT = 0x00000002,
        GLX_PBUFFER_CLOBBER_MASK = 0x08000000,
        GLX_SAMPLE_BUFFERS = 0x186a0,
        GLX_SAMPLES = 0x186a1,
    }

    struct __GLXcontextRec;
    struct __GLXFBConfigRec;

    alias GLXContentID = uint;
    alias GLXPixmap = uint;
    alias GLXDrawable = uint;
    alias GLXPbuffer = uint;
    alias GLXWindow = uint;
    alias GLXFBConfigID = uint;

    alias GLXContext = __GLXcontextRec*;
    alias GLXFBConfig = __GLXFBConfigRec*;

    struct GLXPbufferClobberEvent {
        int         event_type;
        int         draw_type;
        uint        serial;
        Bool        send_event;
        Display*    display;
        GLXDrawable drawable;
        uint        buffer_mask;
        uint        aux_buffer;
        int         x, y;
        int         width, height;
        int         count;
    }

    union GLXEvent {
        GLXPbufferClobberEvent glxpbufferclobber;
        int[24] pad;
    }

    extern ( C ) @nogc nothrow {
        alias da_glXChooseVisual = XVisualInfo* function( Display*,int,int* );
        alias da_glXCopyContext = void function( Display*,GLXContext,GLXContext,uint );
        alias da_glXCreateContext = GLXContext function( Display*,XVisualInfo*,GLXContext,Bool );
        alias da_glXCreateGLXPixmap = GLXPixmap function( Display*,XVisualInfo*,Pixmap );
        alias da_glXDestroyContext = void function( Display*,GLXContext );
        alias da_glXDestroyGLXPixmap = void function( Display*,GLXPixmap );
        alias da_glXGetConfig = int  function( Display*,XVisualInfo*,int,int* );
        alias da_glXGetCurrentContext = GLXContext function();
        alias da_glXGetCurrentDrawable = GLXDrawable function();
        alias da_glXIsDirect = Bool function( Display*,GLXContext );
        alias da_glXMakeCurrent = Bool function( Display*,GLXDrawable,GLXContext );
        alias da_glXQueryExtension = Bool function( Display*,int*,int* );
        alias da_glXQueryVersion = Bool function( Display*,int*,int* );
        alias da_glXSwapBuffers = void function( Display*,GLXDrawable );
        alias da_glXUseXFont = void function( Font,int,int,int );
        alias da_glXWaitGL = void function();
        alias da_glXWaitX = void function();
        alias da_glXGetClientString = char* function( Display*,int );
        alias da_glXQueryServerString = char* function( Display*,int,int );
        alias da_glXQueryExtensionsString = char* function( Display*,int );

        /* GLX 1.3 */
        alias da_glXGetFBConfigs = GLXFBConfig* function( Display*,int,int* );
        alias da_glXChooseFBConfig = GLXFBConfig* function( Display*,int,int*,int* );
        alias da_glXGetFBConfigAttrib = int  function( Display*,GLXFBConfig,int,int* );
        alias da_glXGetVisualFromFBConfig = XVisualInfo* function( Display*,GLXFBConfig );
        alias da_glXCreateWindow = GLXWindow function( Display*,GLXFBConfig,Window,int* );
        alias da_glXDestroyWindow = void function( Display*,GLXWindow );
        alias da_glXCreatePixmap = GLXPixmap function( Display*,GLXFBConfig,Pixmap,int* );
        alias da_glXDestroyPixmap = void function( Display*,GLXPixmap );
        alias da_glXCreatePbuffer = GLXPbuffer function( Display*,GLXFBConfig,int* );
        alias da_glXDestroyPbuffer = void function( Display*,GLXPbuffer );
        alias da_glXQueryDrawable = void function( Display*,GLXDrawable,int,uint* );
        alias da_glXCreateNewContext = GLXContext function( Display*,GLXFBConfig,int,GLXContext,Bool );
        alias da_glXMakeContextCurrent = Bool function( Display*,GLXDrawable,GLXDrawable,GLXContext );
        alias da_glXGetCurrentReadDrawable = GLXDrawable function();
        alias da_glXGetCurrentDisplay = Display* function();
        alias da_glXQueryContext = int  function( Display*,GLXContext,int,int* );
        alias da_glXSelectEvent = void function( Display*,GLXDrawable,uint );
        alias da_glXGetSelectedEvent = void function( Display*,GLXDrawable,uint* );

        /* GLX 1.4+ */
        alias da_glXGetProcAddress = void* function( const( char )* );
    }

    __gshared {
        da_glXChooseVisual glXChooseVisual;
        da_glXCopyContext glXCopyContext;
        da_glXCreateContext glXCreateContext;
        da_glXCreateGLXPixmap glXCreateGLXPixmap;
        da_glXDestroyContext glXDestroyContext;
        da_glXDestroyGLXPixmap glXDestroyGLXPixmap;
        da_glXGetConfig glXGetConfig;
        da_glXGetCurrentContext glXGetCurrentContext;
        da_glXGetCurrentDrawable glXGetCurrentDrawable;
        da_glXIsDirect glXIsDirect;
        da_glXMakeCurrent glXMakeCurrent;
        da_glXQueryExtension glXQueryExtension;
        da_glXQueryVersion glXQueryVersion;
        da_glXSwapBuffers glXSwapBuffers;
        da_glXUseXFont glXUseXFont;
        da_glXWaitGL glXWaitGL;
        da_glXWaitX glXWaitX;
        da_glXGetClientString glXGetClientString;
        da_glXQueryServerString glXQueryServerString;
        da_glXQueryExtensionsString glXQueryExtensionsString;

        /* GLX 1.3 */

        da_glXGetFBConfigs glXGetFBConfigs;
        da_glXChooseFBConfig glXChooseFBConfig;
        da_glXGetFBConfigAttrib glXGetFBConfigAttrib;
        da_glXGetVisualFromFBConfig glXGetVisualFromFBConfig;
        da_glXCreateWindow glXCreateWindow;
        da_glXDestroyWindow glXDestroyWindow;
        da_glXCreatePixmap glXCreatePixmap;
        da_glXDestroyPixmap glXDestroyPixmap;
        da_glXCreatePbuffer glXCreatePbuffer;
        da_glXDestroyPbuffer glXDestroyPbuffer;
        da_glXQueryDrawable glXQueryDrawable;
        da_glXCreateNewContext glXCreateNewContext;
        da_glXMakeContextCurrent glXMakeContextCurrent;
        da_glXGetCurrentReadDrawable glXGetCurrentReadDrawable;
        da_glXGetCurrentDisplay glXGetCurrentDisplay;
        da_glXQueryContext glXQueryContext;
        da_glXSelectEvent glXSelectEvent;
        da_glXGetSelectedEvent glXGetSelectedEvent;

        /* GLX 1.4+ */
        da_glXGetProcAddress glXGetProcAddress;
    }

    package {
        void loadPlatformGL( void delegate( void**, string, bool doThrow ) bindFunc ) {
            bindFunc( cast( void** )&glXChooseVisual, "glXChooseVisual", true );
            bindFunc( cast( void** )&glXCopyContext, "glXCopyContext", true );
            bindFunc( cast( void** )&glXCreateContext, "glXCreateContext", true );
            bindFunc( cast( void** )&glXCreateGLXPixmap, "glXCreateGLXPixmap", true );
            bindFunc( cast( void** )&glXDestroyContext, "glXDestroyContext", true );
            bindFunc( cast( void** )&glXDestroyGLXPixmap, "glXDestroyGLXPixmap", true );
            bindFunc( cast( void** )&glXGetConfig, "glXGetConfig", true );
            bindFunc( cast( void** )&glXGetCurrentContext, "glXGetCurrentContext", true );
            bindFunc( cast( void** )&glXGetCurrentDrawable, "glXGetCurrentDrawable", true );
            bindFunc( cast( void** )&glXIsDirect, "glXIsDirect", true );
            bindFunc( cast( void** )&glXMakeCurrent, "glXMakeCurrent", true );
            bindFunc( cast( void** )&glXQueryExtension, "glXQueryExtension", true );
            bindFunc( cast( void** )&glXQueryVersion, "glXQueryVersion", true );
            bindFunc( cast( void** )&glXSwapBuffers, "glXSwapBuffers", true );
            bindFunc( cast( void** )&glXUseXFont, "glXUseXFont", true );
            bindFunc( cast( void** )&glXWaitGL, "glXWaitGL", true );
            bindFunc( cast( void** )&glXWaitX, "glXWaitX", true );
            bindFunc( cast( void** )&glXGetClientString, "glXGetClientString", true );
            bindFunc( cast( void** )&glXQueryServerString, "glXQueryServerString", true );
            bindFunc( cast( void** )&glXQueryExtensionsString, "glXQueryExtensionsString", true );

            bindFunc( cast( void** )&glXGetFBConfigs, "glXGetFBConfigs", true );
            bindFunc( cast( void** )&glXChooseFBConfig, "glXChooseFBConfig", true );
            bindFunc( cast( void** )&glXGetFBConfigAttrib, "glXGetFBConfigAttrib", true );
            bindFunc( cast( void** )&glXGetVisualFromFBConfig, "glXGetVisualFromFBConfig", true );
            bindFunc( cast( void** )&glXCreateWindow, "glXCreateWindow", true );
            bindFunc( cast( void** )&glXDestroyWindow, "glXDestroyWindow", true );
            bindFunc( cast( void** )&glXCreatePixmap, "glXCreatePixmap", true );
            bindFunc( cast( void** )&glXDestroyPixmap, "glXDestroyPixmap", true );
            bindFunc( cast( void** )&glXCreatePbuffer, "glXCreatePbuffer", true );
            bindFunc( cast( void** )&glXDestroyPbuffer, "glXDestroyPbuffer", true );
            bindFunc( cast( void** )&glXQueryDrawable, "glXQueryDrawable", true );
            bindFunc( cast( void** )&glXCreateNewContext, "glXCreateNewContext", true );
            bindFunc( cast( void** )&glXMakeContextCurrent, "glXMakeContextCurrent", true );
            bindFunc( cast( void** )&glXGetCurrentReadDrawable, "glXGetCurrentReadDrawable", true );
            bindFunc( cast( void** )&glXGetCurrentDisplay, "glXGetCurrentDisplay", true );
            bindFunc( cast( void** )&glXQueryContext, "glXQueryContext", true );
            bindFunc( cast( void** )&glXSelectEvent, "glXSelectEvent", true );
            bindFunc( cast( void** )&glXGetSelectedEvent, "glXGetSelectedEvent", true );

            bindFunc( cast( void** )&glXGetProcAddress, "glXGetProcAddressARB", true );
        }

        void* loadGLFunc( string symName ) {
            return glXGetProcAddress( symName.toStringz() );
        }

        bool hasValidContext() {
            if( glXGetCurrentContext && glXGetCurrentContext() )
                return true;
            return false;
        }
    }
}
