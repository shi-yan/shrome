#import "metal_view.h"

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"
#include "imgui_internal.h"
#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/cef_command_line.h" // Required for CefCommandLine
#include <simd/simd.h>
#include "mycef.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
@class CEFManager;

namespace MTL
{
    class RenderCommandEncoder;
    class Buffer;
}

matrix_float4x4 matrix_ortho(float left, float right, float bottom, float top, float near, float far)
{
    float sx = 2.0f / (right - left);
    float sy = 2.0f / (top - bottom);
    float sz = 2.0f / (near - far);
    float tx = (left + right) / (left - right);
    float ty = (bottom + top) / (bottom - top);
    float tz = (near + far) / (near - far);
    return (matrix_float4x4){{{sx, 0, 0, 0},
                              {0, sy, 0, 0},
                              {0, 0, sz, 0},
                              {tx, ty, tz, 1}}};
}

@interface CEFManager : NSObject
+ (instancetype)sharedManager;
- (void)registerApp:(CefRefPtr<MyApp>)app;
- (void)unregisterApp:(CefRefPtr<MyApp>)app;
- (void)shutdownIfAllClosed;
@end

@implementation AppDelegate

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // ---- 1. Create and Add the CFRunLoopSource ----

    // You must make the very first call to prime the CEF message loop.
    CefDoMessageLoopWork();

    NSLog(@"App is running, CEF message loop is now event-driven...");
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{

    NSLog(@"App terminated, CEF shutdown complete.");

    CefShutdown();
}

@end

@implementation CEFManager
{
    NSMutableArray *_activeApps;
}

+ (instancetype)sharedManager
{
    static CEFManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[CEFManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _activeApps = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)registerApp:(CefRefPtr<MyApp>)app
{
    @synchronized(self)
    {
        NSValue *appValue = [NSValue valueWithPointer:app.get()];
        [_activeApps addObject:appValue];
        NSLog(@"CEF app registered. Active count: %lu", (unsigned long)_activeApps.count);
    }
}

- (void)unregisterApp:(CefRefPtr<MyApp>)app
{
    @synchronized(self)
    {
        NSValue *appValue = [NSValue valueWithPointer:app.get()];
        [_activeApps removeObject:appValue];
        NSLog(@"CEF app unregistered. Active count: %lu", (unsigned long)_activeApps.count);

        if (_activeApps.count == 0)
        {
            NSLog(@"All CEF apps closed, quitting message loop");
            CefQuitMessageLoop();
        }
    }
}

- (void)shutdownIfAllClosed
{
    @synchronized(self)
    {
        if (_activeApps.count == 0)
        {
            NSLog(@"Forcing CEF message loop quit");
            CefQuitMessageLoop();
        }
    }
}

@end

@interface MainMetalView ()
{
    CefRefPtr<MyApp> _app;
}

@end

@implementation MainMetalView
{
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    NSMutableString *_textBuffer;
    BOOL _hasMarkedText;
    NSTextInputContext *_myInputContext;
    // IME state variables
    NSString *_markedTextString;
    NSAttributedString *_markedTextAttributed;
    NSRange _markedRange;
    NSRange _selectedRange;
    std::vector<CefCompositionUnderline> _underlines;
    BOOL _handlingKeyDown;
    BOOL _oldHasMarkedText;
    std::string _textToBeInserted;
    CefRange _setMarkedTextReplacementRange;
    BOOL _unmarkTextCalled;
    int holeWidth;
    int holeHeight;
    int holeX;
    int holeY;
    int viewportWidth;
    int viewportHeight;
    bool shouldHandleMouseEvents;
    bool shouldHandleKeyEvents;
    bool isDragging; // Track if we're in a drag operation
}

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device
{
    self = [super initWithFrame:frame device:device];
    if (self)
    {
        holeWidth = 512;
        holeHeight = 512;
        holeX = 0;
        holeY = 0;
        viewportWidth = frame.size.width;
        viewportHeight = frame.size.height;
        // Enable drawing to work with Metal
        self.device = device;
        self.enableSetNeedsDisplay = NO;
        self.paused = NO;
        self.framebufferOnly = NO;
        self.delegate = self;
        [self setupMetalWithFrame:frame];
        [self setupTextInput];
        // Force initial display
        //[self setNeedsDisplay:YES];

        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        ImGuiIO &io = ImGui::GetIO();
        (void)io;
        io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
                                                              // io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
        io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;     // Enable Docking
        io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;   // Enable Multi-Viewport / Platform Windows
        // Setup Dear ImGui style
        ImGui::StyleColorsDark();
        // ImGui::StyleColorsLight();
        ImGuiStyle &style = ImGui::GetStyle();

        if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
        {
            style.WindowRounding = 0.0f;
            style.Colors[ImGuiCol_WindowBg].w = 1.0f;
        }

        // Setup Renderer backend
        ImGui_ImplMetal_Init(device);
        ImGui_ImplOSX_Init(self);

        CGFloat pixelDensity = [NSScreen.mainScreen backingScaleFactor];
        pixelDensity = pixelDensity > 0 ? pixelDensity : 1.0;
        int normalWinWidth = frame.size.width;
        int normalWinHeight = frame.size.height;

        _app = new MyApp((__bridge MTL::Device *)self.device, normalWinWidth, normalWinHeight, pixelDensity);
        _app->init((__bridge MTL::Device *)self.device, MTLPixelFormatBGRA8Unorm, normalWinWidth, normalWinHeight);

        [self setupCEF]; // Initialize CEF

        [[CEFManager sharedManager] registerApp:_app];

        // Set up notification observers for focus handling
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidResignKey:)
                                                     name:NSWindowDidResignKeyNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];

        // CefDoMessageLoopWork();
    }
    return self;
}

- (NSTextInputContext *)inputContext
{
    if (!_myInputContext)
    {
        _myInputContext = [[NSTextInputContext alloc] initWithClient:self]; // or textInputClient
    }
    return _myInputContext;
}

- (int)setupCEF
{
    int argc = 0;
    char **argv = nullptr; // Dummy argument for CEF
    CefMainArgs main_args(argc, argv);
    int exit_code = CefExecuteProcess(main_args, _app, nullptr);
    if (exit_code >= 0)
    {
        // The sub-process has exited, so the main process should also exit.
        return exit_code;
    }

    CefSettings settings;
    // Required for windowless (offscreen) rendering. Must be set before CefInitialize. [3, 1]
    settings.windowless_rendering_enabled = true;
    settings.external_message_pump = true;
    CefString(&settings.root_cache_path) = get_macos_cache_dir("shrome");

#if !defined(CEF_USE_SANDBOX)
    // Required if you're not using the sandbox. For simplicity in a minimal
    // example, disabling the sandbox is common.
    settings.no_sandbox = true;
#endif

    // If you need to specify a cache path for performance or storage
    // CefString(&settings.cache_path) = "cef_cache";

    if (!CefInitialize(main_args, settings, _app.get(), nullptr))
    { // [1]
        return CefGetExitCode();
    }

    return 0;
}

- (void)doCommandBySelector:(SEL)selector
{
    // Swallow all IME commands, let your own UI handle them
}

- (void)setupMetalWithFrame:(CGRect)frame
{
    NSLog(@"Setting up Metal...");

    // self.device = MTLCreateSystemDefaultDevice();
    _commandQueue = [self.device newCommandQueue];

    // Metal shaders for triangle + coordinate indicators
    NSString *shaderSource = @"#include <metal_stdlib>\n"
                              "using namespace metal;\n"
                              "struct VertexOut {\n"
                              "    float4 position [[position]];\n"
                              "    float4 color;\n"
                              "};\n"
                              "vertex VertexOut vertex_main(uint vid [[vertex_id]]) {\n"
                              "    VertexOut out;\n"
                              "    \n"
                              "    if (vid < 3) {\n"
                              "        // Triangle vertices (first 3 vertices)\n"
                              "        float2 positions[3] = {float2(-0.5, -0.5), float2(0.5, -0.5), float2(0.0, 0.5)};\n"
                              "        out.position = float4(positions[vid], 0.0, 1.0);\n"
                              "        out.color = float4(1.0, 0.5, 0.2, 1.0); // Orange\n"
                              "    } else if (vid < 9) {\n"
                              "        // Origin indicator (bottom-left corner) - vertices 3-8 (2 triangles = square)\n"
                              "        uint localVid = vid - 3;\n"
                              "        float2 corners[6] = {\n"
                              "            float2(-1.0, -1.0), float2(-0.8, -1.0), float2(-1.0, -0.8),  // First triangle\n"
                              "            float2(-0.8, -1.0), float2(-0.8, -0.8), float2(-1.0, -0.8)   // Second triangle\n"
                              "        };\n"
                              "        out.position = float4(corners[localVid], 0.0, 1.0);\n"
                              "        out.color = float4(0.0, 1.0, 0.0, 1.0); // Bright green\n"
                              "    } else if (vid < 15) {\n"
                              "        // Top-left indicator - vertices 9-14\n"
                              "        uint localVid = vid - 9;\n"
                              "        float2 corners[6] = {\n"
                              "            float2(-1.0, 0.8), float2(-0.8, 0.8), float2(-1.0, 1.0),     // First triangle\n"
                              "            float2(-0.8, 0.8), float2(-0.8, 1.0), float2(-1.0, 1.0)      // Second triangle\n"
                              "        };\n"
                              "        out.position = float4(corners[localVid], 0.0, 1.0);\n"
                              "        out.color = float4(1.0, 0.5, 0.0, 1.0); // Orange\n"
                              "    } else if (vid < 21) {\n"
                              "        // Bottom-right indicator - vertices 15-20\n"
                              "        uint localVid = vid - 15;\n"
                              "        float2 corners[6] = {\n"
                              "            float2(0.8, -1.0), float2(1.0, -1.0), float2(0.8, -0.8),     // First triangle\n"
                              "            float2(1.0, -1.0), float2(1.0, -0.8), float2(0.8, -0.8)      // Second triangle\n"
                              "        };\n"
                              "        out.position = float4(corners[localVid], 0.0, 1.0);\n"
                              "        out.color = float4(0.0, 0.0, 1.0, 1.0); // Blue\n"
                              "    } else {\n"
                              "        // Top-right indicator - vertices 21-26\n"
                              "        uint localVid = vid - 21;\n"
                              "        float2 corners[6] = {\n"
                              "            float2(0.8, 0.8), float2(1.0, 0.8), float2(0.8, 1.0),        // First triangle\n"
                              "            float2(1.0, 0.8), float2(1.0, 1.0), float2(0.8, 1.0)         // Second triangle\n"
                              "        };\n"
                              "        out.position = float4(corners[localVid], 0.0, 1.0);\n"
                              "        out.color = float4(1.0, 0.0, 1.0, 1.0); // Magenta\n"
                              "    }\n"
                              "    \n"
                              "    return out;\n"
                              "}\n"
                              "fragment float4 fragment_main(VertexOut in [[stage_in]]) {\n"
                              "    return in.color;\n"
                              "}\n";

    NSError *error;
    id<MTLLibrary> library = [self.device newLibraryWithSource:shaderSource options:nil error:&error];
    if (error)
    {
        NSLog(@"Shader compilation error: %@", error);
        return;
    }

    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];

    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;

    _pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (error)
    {
        NSLog(@"Pipeline state error: %@", error);
    }
}

- (void)setupTextInput
{
    _textBuffer = [[NSMutableString alloc] init];
    _hasMarkedText = NO;
    _markedRange = NSMakeRange(NSNotFound, 0);
    _selectedRange = NSMakeRange(0, 0);

    self.inputText = @"";

    // Initialize IME positioning
    self.textCursorPosition = NSMakePoint(100, 100); // Default cursor position
    self.lastMousePosition = NSMakePoint(0, 0);
    self.followMouse = NO; // Set to YES to follow mouse, NO to follow text cursor
}

- (void)cleanup
{
    NSLog(@"MainMetalView cleanup called");

    // Remove notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_app)
    {
        _app->close(true);
        int timeout = 100;
        while (!_app->is_browser_closed() && timeout > 0)
        {
            CefDoMessageLoopWork(); // Or sleep a bit i
            [NSThread sleepForTimeInterval:0.1];
            timeout--;
        }

        if (timeout <= 0)
        {
            NSLog(@"Warning: Browser close timeout reached");
        }

        [[CEFManager sharedManager] unregisterApp:_app];
        // CefQuitMessageLoop();
        _app.reset();
        _app = nullptr;
    }
    // Cleanup
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplOSX_Shutdown();
    ImGui::DestroyContext();
    self.delegate = nil;
    _myInputContext = nil;
}

#pragma mark - Focus and Window Notifications

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    // Only respond to notifications from our window
    if (notification.object == self.window)
    {
        NSLog(@"MainMetalView window became key - trying to become first responder");

        // Try to become first responder
        [self.window makeFirstResponder:self];

        // Reset event handling flags
        shouldHandleMouseEvents = true;
        shouldHandleKeyEvents = true;

        // Notify CEF that we regained focus
        if (_app && _app->get_browser())
        {
            _app->get_browser()->GetHost()->SetFocus(true);
        }
    }
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    // Only respond to notifications from our window
    if (notification.object == self.window)
    {
        NSLog(@"MainMetalView window resigned key");

        // Notify CEF that we lost focus
        if (_app && _app->get_browser())
        {
            _app->get_browser()->GetHost()->SetFocus(false);
        }
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    NSLog(@"Application became active");

    // App regained focus - try to reclaim first responder if our window is key
    if (self.window.isKeyWindow)
    {
        [self.window makeFirstResponder:self];
    }
}

void SetupDockspace(ImGuiID dockspaceID)
{
    // Clear any previous layout
    ImGui::DockBuilderRemoveNode(dockspaceID);

    // Create a new empty dock node
    ImGui::DockBuilderAddNode(dockspaceID, ImGuiDockNodeFlags_DockSpace);

    // Get the ID of the central node.
    // The central node ID is the same as the dockspace ID itself.
    // However, if you've added other nodes, you can explicitly get it.
    ImGuiID centralNodeID = dockspaceID;

    // Split the dockspace into left/right and top/bottom nodes if you want other windows
    // For this example, we just set the central node, but you can add more like this:
    // ImGuiID leftNodeID, rightNodeID;
    // ImGui::DockBuilderSplitNode(dockspaceID, ImGuiDir_Left, 0.2f, &leftNodeID, &centralNodeID);

    // Dock your custom rendering window into the central node
    // "MyRenderWindow" is the title of the window you want to be the central node.
    ImGui::DockBuilderDockWindow("ShromeWindow", centralNodeID);

    // You can dock other windows as well
    // ImGui::DockBuilderDockWindow("OtherWindow", leftNodeID);

    // Tell ImGui to apply the layout
    ImGui::DockBuilderFinish(dockspaceID);
}

// MTKViewDelegate method - called automatically every frame
- (void)drawInMTKView:(MTKView *)view
{
    ImGui::SetMouseCursor(_app->get_cursor_type());
    // Process CEF message loop work
    CefDoMessageLoopWork();

    // Request new frame BEFORE starting Metal rendering
    _app->request_new_frame();

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize.x = view.bounds.size.width;
    io.DisplaySize.y = view.bounds.size.height;

    CGFloat framebufferScale = view.window.screen.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;

    io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);

    // Metal rendering
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
    if (renderPassDescriptor)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.2, 0.3, 0.5, 1.0);

        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        //[renderEncoder setRenderPipelineState:_pipelineState];
        // Draw triangle (3 vertices) + coordinate indicators (24 vertices) = 27 total
        //[renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:27];

        // [renderEncoder pushDebugGroup:@"Metal View Rendering"];

        // _app->encode_render_command((__bridge MTL::RenderCommandEncoder *)renderEncoder);

        // [renderEncoder popDebugGroup];

        // NSLog(@"MTKView drawInMTKView called - rendering Metal content");

        // Start the Dear ImGui frame
        ImGui_ImplMetal_NewFrame(renderPassDescriptor);
        ImGui_ImplOSX_NewFrame(view);
        ImGui::NewFrame();

        {

            // Begin the main dockspace
            ImGuiWindowFlags windowFlags = /*ImGuiWindowFlags_MenuBar |*/ ImGuiWindowFlags_NoDocking;
            ImGuiViewport *viewport = ImGui::GetMainViewport();
            ImGui::SetNextWindowPos(viewport->WorkPos);
            ImGui::SetNextWindowSize(viewport->WorkSize);
            ImGui::SetNextWindowViewport(viewport->ID);
            ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
            ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
            windowFlags |= ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove;
            windowFlags |= ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoNavFocus;

            ImGui::Begin("DockSpace", nullptr, windowFlags);
            ImGui::PopStyleVar(2);

            ImGuiID dockspaceID = ImGui::GetID("MyDockSpace");

            // Check if we need to set up the dockspace layout.
            // This is typically done only once at the start of the application.
            // You can also add logic to recreate the layout if the main window size changes drastically.
            if (ImGui::DockBuilderGetNode(dockspaceID) == nullptr)
            {
                SetupDockspace(dockspaceID);
            }

            ImGui::DockSpace(dockspaceID, ImVec2(0.0f, 0.0f), ImGuiDockNodeFlags_PassthruCentralNode);

            // Get the central dock node
            // ImGuiDockNode *centralNode = ImGui::DockBuilderGetCentralNode(dockspaceID);

            // Check if the central node exists
            /*   if (centralNode)
               {
                   ImGuiViewport *viewport = ImGui::GetMainViewport();
                   ImVec2 viewportPos = viewport->Pos;
                   ImVec2 viewportSize = viewport->Size;
                   ImVec2 centralPos = centralNode->Pos;
                   ImVec2 centralSize = centralNode->Size;

                   int metalViewportX = centralPos.x - viewportPos.x;
                   int metalViewportY = centralPos.y - viewportPos.y;
                   int metalViewportWidth = centralSize.x;
                   int metalViewportHeight = centralSize.y;

                   // Now you have the geometry of the central hole!
                   if (metalViewportWidth != holeWidth || metalViewportHeight != holeHeight)
                   {
                       CGFloat pixelDensity = [NSScreen.mainScreen backingScaleFactor];
                       pixelDensity = pixelDensity > 0 ? pixelDensity : 1.0;
                       _app->update_render_handler_dimensions((int)centralSize.x, (int)centralSize.y, (int)pixelDensity);

                       // Notify CEF about the size change
                       if (_app && _app->get_browser() && _app->get_browser()->IsValid())
                       {
                           _app->get_browser()->GetHost()->WasResized();
                       }
                   }

                   if (metalViewportX != holeX || metalViewportY != holeY || metalViewportWidth != holeWidth || metalViewportHeight != holeHeight ||
                       (int)viewportSize.x != viewportWidth || (int)viewportSize.y != viewportHeight) {
                       _app->update_geometry(metalViewportX, metalViewportY, metalViewportWidth, metalViewportHeight, (int)viewportSize.x, (int)viewportSize.y);
                   }

                   holeWidth = metalViewportWidth;
                   holeHeight = metalViewportHeight;
                   holeX = metalViewportX;
                   holeY = metalViewportY;
                   viewportWidth = (int)viewportSize.x;
                   viewportHeight = (int)viewportSize.y;
               }*/

            // End the main dockspace window
            ImGui::End();
        }

        // Our state (make them static = more or less global) as a convenience to keep the example terse.
        static bool show_demo_window = true;
        static bool show_another_window = false;
        // static ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

        // 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
        if (show_demo_window)
            ImGui::ShowDemoWindow(&show_demo_window);

        // 2. Browser Controls window
        {
            static char url_buffer[512] = "https://www.example.com";

            ImGui::Begin("Controls");

            // URL input and navigation controls
            ImGui::Text("URL:");
            ImGui::SetNextItemWidth(-150); // Leave space for Go button
            ImGui::InputText("##url", url_buffer, sizeof(url_buffer));
            ImGui::SameLine();
            if (ImGui::Button("Go"))
            {
                if (_app && _app->get_browser() && _app->get_browser()->IsValid())
                {
                    _app->get_browser()->GetMainFrame()->LoadURL(url_buffer);
                }
            }

            ImGui::Separator();

            // Navigation buttons
            if (ImGui::Button("Back"))
            {
                if (_app && _app->get_browser() && _app->get_browser()->IsValid())
                {
                    _app->get_browser()->GoBack();
                }
            }
            ImGui::SameLine();
            if (ImGui::Button("Reload"))
            {
                if (_app && _app->get_browser() && _app->get_browser()->IsValid())
                {
                    _app->get_browser()->Reload();
                }
            }
            ImGui::SameLine();
            if (ImGui::Button("DevTools"))
            {
                if (_app)
                {
                    _app->show_dev_tools();
                }
            }

            ImGui::Separator();

            // Zoom controls
            if (_app)
            {
                double zoom_percentage = _app->get_zoom_percentage();
                ImGui::Text("Zoom: %.0f%%", zoom_percentage);
            }
            else
            {
                ImGui::Text("Zoom: 100%%");
            }
            ImGui::SameLine();
            if (ImGui::Button("Zoom In (+)"))
            {
                if (_app)
                {
                    _app->zoom_in();
                }
            }
            ImGui::SameLine();
            if (ImGui::Button("Zoom Out (-)"))
            {
                if (_app)
                {
                    _app->zoom_out();
                }
            }
            ImGui::SameLine();
            if (ImGui::Button("Reset (0)"))
            {
                if (_app)
                {
                    _app->zoom_reset();
                }
            }

            ImGui::Separator();

            // Keep the demo window checkbox for testing
            ImGui::Checkbox("Demo Window", &show_demo_window);
            ImGui::Checkbox("Another Window", &show_another_window);

            ImGui::End();
        }

        // 3. Show another simple window.
        if (show_another_window)
        {
            ImGui::Begin("Another Window", &show_another_window); // Pass a pointer to our bool variable (the window will have a closing button that will clear the bool when clicked)
            ImGui::Text("Hello from another window!");
            if (ImGui::Button("Close Me"))
                show_another_window = false;
            ImGui::End();
        }

        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
        ImGuiWindowFlags windowFlags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove;
        windowFlags |= ImGuiWindowFlags_NoBringToFrontOnFocus | ImGuiWindowFlags_NoNavFocus | ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoBackground;

        ImGui::Begin("ShromeWindow", nullptr, windowFlags);
        ImGui::PopStyleVar(2);
        if (ImGui::IsWindowHovered())
        {
            shouldHandleMouseEvents = true;

            // If we should be handling events but aren't first responder, try to reclaim
            if (self.window.isKeyWindow && self.window.firstResponder != self)
            {
                [self.window makeFirstResponder:self];
            }
        }
        else
        {
            shouldHandleMouseEvents = false;
        }

        // This is a common pattern to check for focus
        if (ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows))
        {
            shouldHandleKeyEvents = true;

            // If we should be handling events but aren't first responder, try to reclaim
            if (self.window.isKeyWindow && self.window.firstResponder != self)
            {
                [self.window makeFirstResponder:self];
            }
        }
        else
        {
            shouldHandleKeyEvents = false;
        }

        ImVec2 contentSize = ImGui::GetContentRegionAvail();
        ImVec2 startCursorPos = ImGui::GetCursorPos();
        ImVec2 windowPos = ImGui::GetWindowPos();
        // std::cout << "Window Position: " << windowPos.x << ", " << windowPos.y << std::endl;
        ImGuiViewport *viewport = ImGui::GetMainViewport();
        ImVec2 viewportPos = viewport->Pos;
        // ... resize framebuffer and render your scene
        holeX = (int)startCursorPos.x + (int)windowPos.x - (int)viewportPos.x;
        holeY = (int)startCursorPos.y + (int)windowPos.y - (int)viewportPos.y;
        if (contentSize.x != holeWidth || contentSize.y != holeHeight)
        {
            CGFloat pixelDensity = [NSScreen.mainScreen backingScaleFactor];
            pixelDensity = pixelDensity > 0 ? pixelDensity : 1.0;
            _app->update_render_handler_dimensions((int)contentSize.x, (int)contentSize.y, (int)pixelDensity);

            // Notify CEF about the size change
            if (_app && _app->get_browser() && _app->get_browser()->IsValid())
            {
                _app->get_browser()->GetHost()->WasResized();
            }
            holeWidth = contentSize.x;
            holeHeight = contentSize.y;
        }

        // Prepare rendering (composite if needed)
        if (_app)
        {
            _app->prepare_for_render();
        }

        // Display the composite texture (main + popup) or fall back to main texture
        MTL::Texture *display_texture = (_app && _app->m_should_show_popup && _app->m_popup_texture && _app->m_composite_texture)
                                        ? _app->m_composite_texture : (_app ? _app->m_texture : nullptr);

        if (display_texture)
        {
            ImTextureID myFramebufferTextureID = reinterpret_cast<ImTextureID>(display_texture);
            ImGui::Image(myFramebufferTextureID, contentSize, ImVec2(0, 0), ImVec2(1, 1));
        }
        ImGui::End();

        // Handle context menu as a regular ImGui window (not popup)
        static ImVec2 context_menu_pos = ImVec2(0, 0);
        static bool context_menu_pos_set = false;

        if (_app && _app->should_show_context_menu())
        {
            // Only capture mouse position once when menu is first shown
            if (!context_menu_pos_set)
            {
                context_menu_pos = ImGui::GetMousePos();
                context_menu_pos_set = true;
                std::cout << "Showing context menu at: " << context_menu_pos.x << ", " << context_menu_pos.y << std::endl;
            }

            ImGui::SetNextWindowPos(context_menu_pos);
            ImGui::SetNextWindowSize(ImVec2(150, 0)); // Auto height

            ImGuiWindowFlags flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                                     ImGuiWindowFlags_NoMove | ImGuiWindowFlags_AlwaysAutoResize |
                                     ImGuiWindowFlags_NoSavedSettings;

            if (ImGui::Begin("ContextMenu", nullptr, flags))
            {
                // Manually render context menu items here
                if (ImGui::MenuItem("Undo"))
                {
                    _app->undo();
                    _app->hide_context_menu();
                }
                if (ImGui::MenuItem("Redo"))
                {
                    _app->redo();
                    _app->hide_context_menu();
                }
                ImGui::Separator();
                if (ImGui::MenuItem("Cut"))
                {
                    _app->cut();
                    _app->hide_context_menu();
                }
                if (ImGui::MenuItem("Copy"))
                {
                    _app->copy();
                    _app->hide_context_menu();
                }
                if (ImGui::MenuItem("Paste"))
                {
                    _app->paste();
                    _app->hide_context_menu();
                }
                ImGui::Separator();
                if (ImGui::MenuItem("Select All"))
                {
                    _app->select_all();
                    _app->hide_context_menu();
                }

                // Close if clicking outside the menu
                if (!ImGui::IsWindowHovered() && ImGui::IsMouseClicked(0))
                {
                    _app->hide_context_menu();
                }
            }
            ImGui::End();
        }
        else
        {
            // Reset position flag when context menu is hidden
            context_menu_pos_set = false;
        }

        // Rendering
        ImGui::Render();
        ImDrawData *draw_data = ImGui::GetDrawData();

        [renderEncoder pushDebugGroup:@"Dear ImGui rendering"];
        ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);
        [renderEncoder popDebugGroup];
        [renderEncoder endEncoding];

        // Present
        [commandBuffer presentDrawable:view.currentDrawable];
        [commandBuffer commit];

        // Update and Render additional Platform Windows
        if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
        {
            ImGui::UpdatePlatformWindows();
            ImGui::RenderPlatformWindowsDefault();
        }
    }
}

// MTKViewDelegate method - called when view size changes
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // here size is width * pixel_density.
}

// Override setFrame to handle view bounds changes
- (void)setFrame:(NSRect)frameRect
{
    [super setFrame:frameRect];

    // Check for window resize and get the available size
    /*

            CGFloat pixelDensity = [NSScreen.mainScreen backingScaleFactor];
            pixelDensity = pixelDensity > 0 ? pixelDensity : 1.0;
            _app->update_render_handler_dimensions((int)contentSize.x, (int)contentSize.y, (int)pixelDensity);

            // Notify CEF about the size change
            if (_app && _app->get_browser() && _app->get_browser()->IsValid())
            {
                _app->get_browser()->GetHost()->WasResized();
            }
        */
    // Update render handler dimensions and pixel density
}

#pragma mark - Event Handling

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    BOOL result = [super becomeFirstResponder];
    if (result)
    {
        NSLog(@"MainMetalView became first responder");

        // Reset event handling state
        shouldHandleMouseEvents = true;
        shouldHandleKeyEvents = true;

        // Notify CEF
        if (_app && _app->get_browser())
        {
            _app->get_browser()->GetHost()->SetFocus(true);
        }
    }
    return result;
}

- (BOOL)resignFirstResponder
{
    NSLog(@"MainMetalView resigned first responder");

    // Notify CEF
    if (_app && _app->get_browser())
    {
        _app->get_browser()->GetHost()->SetFocus(false);
    }

    return [super resignFirstResponder];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    // Let CEF handle all keyboard shortcuts (Cmd+C, Cmd+V, Cmd+X, etc.)
    // This allows OnPreKeyEvent in mycef.h to handle them consistently
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();



    // If CEF has focus and ImGui wants keyboard, send to CEF
    if (io.WantCaptureKeyboard && shouldHandleKeyEvents)
    {
        if ([event type] != NSEventTypeFlagsChanged)
        {
            [self handleKeyEventBeforeTextInputClient:event];

            // Let the input method system handle this
            [self.inputContext handleEvent:event];

            CefKeyEvent keyEvent;
            [self getKeyEvent:keyEvent forEvent:event];

            [self handleKeyEventAfterTextInputClient:keyEvent];
        }
        return;
    }

        // Always let ImGui process the event first
    if (!ImGui_ImplOSX_HandleEvent(event, self))
    {
        [super keyDown:event];
    }

    // If ImGui wants keyboard and CEF doesn't have focus, let ImGui handle it
    if (io.WantCaptureKeyboard && !shouldHandleKeyEvents)
    {
        // ImGui will handle this through its own text input system
        [self interpretKeyEvents:@[ event ]];
        return;
    }
}

- (void)keyUp:(NSEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();


    // If CEF has focus and ImGui wants keyboard, send to CEF
    if (io.WantCaptureKeyboard && shouldHandleKeyEvents)
    {
        CefKeyEvent keyEvent;
        [self getKeyEvent:keyEvent forEvent:event];
        keyEvent.type = KEYEVENT_KEYUP;

        _app->inject_key_event(keyEvent);
        return;
    }


    // Always let ImGui process the event first
    if (!ImGui_ImplOSX_HandleEvent(event, self))
    {
        [super keyUp:event];
    }
}

- (void)flagsChanged:(NSEvent *)event
{
    if ([self isKeyUpEvent:event])
    {
        [self keyUp:event];
    }
    else
    {
        [self keyDown:event];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    if (io.WantCaptureMouse && shouldHandleMouseEvents)
    {
        NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];

        int mouseX = static_cast<int>(locationInView.x) - holeX;
        int mouseY = static_cast<int>(self.bounds.size.height - locationInView.y) - holeY;
        std::cout << "holex " << holeX << " holey " << holeY << std::endl;
        std::cout << "Mouse down at: (" << mouseX << ", " << mouseY << ")" << std::endl;

        // Update cursor position to mouse click location
        self.textCursorPosition = locationInView;
        self.lastMousePosition = locationInView;

        // NSLog(@"Text cursor moved to: (%.1f, %.1f)", locationInView.x, locationInView.y);
        [self setNeedsDisplay:YES];

        // Convert to CEF mouse event and inject
        CefMouseEvent mouseEvent;
        // Convert from NSView coordinates (bottom-left origin) to CEF coordinates (top-left origin)
        mouseEvent.x = mouseX;
        mouseEvent.y = mouseY;
        mouseEvent.modifiers = [self convertModifiers:event];

        CefBrowserHost::MouseButtonType buttonType = CefBrowserHost::MouseButtonType::MBT_LEFT;
        if ([event buttonNumber] == 1)
        {
            buttonType = CefBrowserHost::MouseButtonType::MBT_RIGHT;
        }
        else if ([event buttonNumber] == 2)
        {
            buttonType = CefBrowserHost::MouseButtonType::MBT_MIDDLE;
        }

        _app->inject_mouse_up_down(mouseEvent, buttonType, false, [event clickCount]);

        // Start drag tracking
        isDragging = true;
    }
}

- (void)mouseUp:(NSEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    if (io.WantCaptureMouse && shouldHandleMouseEvents)
    {
        NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];

        // Convert to CEF mouse event and inject
        CefMouseEvent mouseEvent;
        // Convert from NSView coordinates (bottom-left origin) to CEF coordinates (top-left origin)
        mouseEvent.x = static_cast<int>(locationInView.x) - holeX;
        mouseEvent.y = static_cast<int>(self.bounds.size.height - locationInView.y) - holeY;
        mouseEvent.modifiers = [self convertModifiers:event];

        CefBrowserHost::MouseButtonType buttonType = CefBrowserHost::MouseButtonType::MBT_LEFT;
        if ([event buttonNumber] == 1)
        {
            buttonType = CefBrowserHost::MouseButtonType::MBT_RIGHT;
        }
        else if ([event buttonNumber] == 2)
        {
            buttonType = CefBrowserHost::MouseButtonType::MBT_MIDDLE;
        }

        _app->inject_mouse_up_down(mouseEvent, buttonType, true, [event clickCount]);

        // End drag tracking
        isDragging = false;
    }
}

- (void)rightMouseDown:(NSEvent *)event
{
    [self mouseDown:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    [self mouseUp:event];
}

- (void)otherMouseDown:(NSEvent *)event
{
    [self mouseDown:event];
}

- (void)otherMouseUp:(NSEvent *)event
{
    [self mouseUp:event];
}

- (void)scrollWheel:(NSEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    if (io.WantCaptureMouse && shouldHandleMouseEvents)
    {
        // Convert scroll wheel event to CEF mouse wheel event
        CefMouseEvent mouseEvent;
        NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];
        // Convert from NSView coordinates (bottom-left origin) to CEF coordinates (top-left origin)
        mouseEvent.x = static_cast<int>(locationInView.x) - holeX;
        mouseEvent.y = static_cast<int>(self.bounds.size.height - locationInView.y) - holeY;
        mouseEvent.modifiers = [self convertModifiers:event];

        int deltaX = static_cast<int>([event scrollingDeltaX]);
        int deltaY = static_cast<int>([event scrollingDeltaY]);

        _app->inject_mouse_wheel(mouseEvent, deltaX, deltaY);

        // NSLog(@"mouse scroll at (%.1f, %.1f) with delta (%d, %d)  (%f, %f)",
        //       locationInView.x, locationInView.y, deltaX, deltaY, [event scrollingDeltaX], [event scrollingDeltaY]);
    }
}

// Helper method to convert AppKit event to CEF modifier flags
- (uint32_t)convertModifiers:(NSEvent *)event
{
    uint32_t cefModifiers = 0;

    NSUInteger appKitModifiers = [event modifierFlags];

    if (appKitModifiers & NSEventModifierFlagCommand)
    {
        cefModifiers |= EVENTFLAG_COMMAND_DOWN;
    }
    if (appKitModifiers & NSEventModifierFlagShift)
    {
        cefModifiers |= EVENTFLAG_SHIFT_DOWN;
    }
    if (appKitModifiers & NSEventModifierFlagOption)
    {
        cefModifiers |= EVENTFLAG_ALT_DOWN;
    }
    if (appKitModifiers & NSEventModifierFlagControl)
    {
        cefModifiers |= EVENTFLAG_CONTROL_DOWN;
    }
    if (appKitModifiers & NSEventModifierFlagCapsLock)
    {
        cefModifiers |= EVENTFLAG_CAPS_LOCK_ON;
    }
    /* if (appKitModifiers & NSEventModifierFlagFunction) {
         cefModifiers |= EVENTFLAG_FUNCTION_DOWN;
     }*/
    if (appKitModifiers & NSEventModifierFlagNumericPad)
    {
        cefModifiers |= EVENTFLAG_NUM_LOCK_ON;
    }

    // Mouse buttons - based on event type
    switch ([event type])
    {
    case NSEventTypeLeftMouseDragged:
    case NSEventTypeLeftMouseDown:
    case NSEventTypeLeftMouseUp:
        cefModifiers |= EVENTFLAG_LEFT_MOUSE_BUTTON;
        break;
    case NSEventTypeRightMouseDragged:
    case NSEventTypeRightMouseDown:
    case NSEventTypeRightMouseUp:
        cefModifiers |= EVENTFLAG_RIGHT_MOUSE_BUTTON;
        break;
    case NSEventTypeOtherMouseDragged:
    case NSEventTypeOtherMouseDown:
    case NSEventTypeOtherMouseUp:
        cefModifiers |= EVENTFLAG_MIDDLE_MOUSE_BUTTON;
        break;
    default:
        break;
    }

    return cefModifiers;
}

// Helper method to convert NSEvent to CefKeyEvent
- (void)getKeyEvent:(CefKeyEvent &)keyEvent forEvent:(NSEvent *)event
{
    if ([event type] == NSEventTypeKeyDown || [event type] == NSEventTypeKeyUp)
    {
        NSString *s = [event characters];
        if ([s length] > 0)
        {
            keyEvent.character = [s characterAtIndex:0];
        }

        s = [event charactersIgnoringModifiers];
        if ([s length] > 0)
        {
            keyEvent.unmodified_character = [s characterAtIndex:0];
        }
    }

    if ([event type] == NSEventTypeFlagsChanged)
    {
        keyEvent.character = 0;
        keyEvent.unmodified_character = 0;
    }

    keyEvent.native_key_code = [event keyCode];
    keyEvent.modifiers = [self convertModifiers:event];
}

// Helper method to check if it's a key up event
- (BOOL)isKeyUpEvent:(NSEvent *)event
{
    if ([event type] != NSEventTypeFlagsChanged)
    {
        return [event type] == NSEventTypeKeyUp;
    }

    // Check for modifier key releases
    switch ([event keyCode])
    {
    case 54: // Right Command
    case 55: // Left Command
        return ([event modifierFlags] & NSEventModifierFlagCommand) == 0;

    case 57: // Capslock
        return ([event modifierFlags] & NSEventModifierFlagCapsLock) == 0;

    case 56: // Left Shift
    case 60: // Right Shift
        return ([event modifierFlags] & NSEventModifierFlagShift) == 0;

    case 58: // Left Alt
    case 61: // Right Alt
        return ([event modifierFlags] & NSEventModifierFlagOption) == 0;

    case 59: // Left Ctrl
    case 62: // Right Ctrl
        return ([event modifierFlags] & NSEventModifierFlagControl) == 0;

    case 63: // Function
        return ([event modifierFlags] & NSEventModifierFlagFunction) == 0;
    }
    return false;
}

// Helper method to check if it's a keypad event
- (BOOL)isKeyPadEvent:(NSEvent *)event
{
    if ([event modifierFlags] & NSEventModifierFlagNumericPad)
    {
        return true;
    }

    switch ([event keyCode])
    {
    case 71: // Clear
    case 81: // =
    case 75: // /
    case 67: // *
    case 78: // -
    case 69: // +
    case 76: // Enter
    case 65: // .
    case 82: // 0
    case 83: // 1
    case 84: // 2
    case 85: // 3
    case 86: // 4
    case 87: // 5
    case 88: // 6
    case 89: // 7
    case 91: // 8
    case 92: // 9
        return true;
    }

    return false;
}

// IME helper methods
- (void)handleKeyEventBeforeTextInputClient:(NSEvent *)keyEvent
{
    _oldHasMarkedText = _hasMarkedText;
    _handlingKeyDown = YES;

    // Clear IME state variables
    _textToBeInserted.clear();
    _hasMarkedText = NO;
    _markedTextString = nil;
    _markedTextAttributed = nil;
    _underlines.clear();
    _setMarkedTextReplacementRange = CefRange::InvalidRange();
    _unmarkTextCalled = NO;
}

- (void)handleKeyEventAfterTextInputClient:(CefKeyEvent)keyEvent
{
    _handlingKeyDown = NO;

    // Send keypress and/or composition related events
    if (!_hasMarkedText && !_oldHasMarkedText && _textToBeInserted.length() <= 1)
    {
        keyEvent.type = KEYEVENT_KEYDOWN;
        _app->inject_key_event(keyEvent);

        // Don't send a CHAR event for non-char keys like arrows, function keys and clear
        if (keyEvent.modifiers & (EVENTFLAG_IS_KEY_PAD))
        {
            if (keyEvent.native_key_code == 71)
            {
                return;
            }
        }

        keyEvent.type = KEYEVENT_CHAR;
        _app->inject_key_event(keyEvent);
    }

    // If the text to be inserted contains multiple characters then send the text to the browser
    BOOL textInserted = NO;
    if (_textToBeInserted.length() > ((_hasMarkedText || _oldHasMarkedText) ? 0u : 1u))
    {
        _app->inject_ime_commit_text(_textToBeInserted, CefRange::InvalidRange(), 0);
        _textToBeInserted.clear();
    }

    // Update or cancel the composition
    if (_hasMarkedText && _markedTextString.length)
    {
        // Update the composition by sending marked text to the browser
        _app->inject_ime_set_composition([_markedTextString UTF8String], _underlines,
                                         _setMarkedTextReplacementRange,
                                         CefRange(static_cast<uint32_t>(_selectedRange.location),
                                                  static_cast<uint32_t>(NSMaxRange(_selectedRange))));
    }
    else if (_oldHasMarkedText && !_hasMarkedText && !textInserted)
    {
        // Complete or cancel the composition
        if (_unmarkTextCalled)
        {
            _app->inject_ime_finish_composing_text(false);
        }
        else
        {
            _app->inject_ime_cancel_composition();
        }
    }

    _setMarkedTextReplacementRange = CefRange::InvalidRange();
}

// Helper method to extract underlines from attributed string
- (void)extractUnderlines:(NSAttributedString *)string
{
    _underlines.clear();

    int length = static_cast<int>([[string string] length]);
    int i = 0;
    while (i < length)
    {
        NSRange range;
        NSDictionary *attrs = [string attributesAtIndex:i
                                  longestEffectiveRange:&range
                                                inRange:NSMakeRange(i, length - i)];
        NSNumber *style = [attrs objectForKey:NSUnderlineStyleAttributeName];
        if (style)
        {
            cef_color_t color = 0xFF000000; // Black
            if (NSColor *colorAttr = [attrs objectForKey:NSUnderlineColorAttributeName])
            {
                NSColor *rgbColor = [colorAttr colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
                CGFloat r, g, b, a;
                [rgbColor getRed:&r green:&g blue:&b alpha:&a];
                color = (static_cast<int>(lroundf(255.0f * a)) << 24) |
                        (static_cast<int>(lroundf(255.0f * r)) << 16) |
                        (static_cast<int>(lroundf(255.0f * g)) << 8) |
                        (static_cast<int>(lroundf(255.0f * b)));
            }

            cef_composition_underline_t line = {
                sizeof(cef_composition_underline_t),
                {static_cast<uint32_t>(range.location),
                 static_cast<uint32_t>(NSMaxRange(range))},
                color,
                0,
                [style intValue] > 1};
            _underlines.push_back(line);
        }
        i = static_cast<int>(range.location + range.length);
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    if (shouldHandleMouseEvents == true || isDragging)
    {
        if (self.followMouse)
        {
            NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];
            self.lastMousePosition = locationInView;
        }

        // Convert to CEF mouse event and inject
        NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];
        CefMouseEvent mouseEvent;
        // Convert from NSView coordinates (bottom-left origin) to CEF coordinates (top-left origin)
        mouseEvent.x = static_cast<int>(locationInView.x) - holeX;
        mouseEvent.y = static_cast<int>(self.bounds.size.height - locationInView.y) - holeY;
        std::cout << "mouse motion raw: (" << locationInView.x << ", " << locationInView.y << ") converted: (" << mouseEvent.x << ", " << mouseEvent.y << ") holes: (" << holeX << ", " << holeY << ")" << std::endl;
        mouseEvent.modifiers = [self convertModifiers:event];

        _app->inject_mouse_motion(mouseEvent);
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    [self mouseMoved:event];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];

    // Remove existing tracking area
    for (NSTrackingArea *area in [self trackingAreas])
    {
        [self removeTrackingArea:area];
    }

    // Add new tracking area for mouse movement
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
               owner:self
            userInfo:nil];
    [self addTrackingArea:trackingArea];
}

// Method to programmatically set cursor position
- (void)setCursorPosition:(NSPoint)position
{
    self.textCursorPosition = position;
    NSLog(@"Cursor position set to: (%.1f, %.1f)", position.x, position.y);
    [self setNeedsDisplay:YES];
}

- (void)toggleMouseFollowing
{
    self.followMouse = !self.followMouse;
    NSLog(@"Mouse following toggled to: %@", self.followMouse ? @"ON" : @"OFF");
    [self setNeedsDisplay:YES];
}

- (void)drawCoordinateSystemIndicators
{
    // Draw coordinate system indicators to demonstrate AppKit's bottom-left origin
    // Making them very prominent to ensure visibility

    NSLog(@"Drawing coordinate indicators...");

    // Origin point (0,0) - bottom-left corner - VERY LARGE AND BRIGHT
    NSRect originRect = NSMakeRect(0, 0, 80, 80);
    [[NSColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:0.8] setFill];
    NSRectFill(originRect);

    // Add a border
    [[NSColor blackColor] setStroke];
    NSBezierPath *originBorder = [NSBezierPath bezierPathWithRect:originRect];
    [originBorder setLineWidth:3.0];
    [originBorder stroke];

    [@"(0,0) ORIGIN" drawAtPoint:NSMakePoint(10, 10)
                  withAttributes:@{
                      NSForegroundColorAttributeName : [NSColor blackColor],
                      NSFontAttributeName : [NSFont boldSystemFontOfSize:16]
                  }];

    // Top-left corner (what many expect to be origin)
    NSRect topLeftRect = NSMakeRect(0, self.bounds.size.height - 40, 80, 40);
    [[NSColor orangeColor] setFill];
    NSRectFill(topLeftRect);

    NSString *topLeftText = [NSString stringWithFormat:@"(0,%.0f)", self.bounds.size.height];
    [topLeftText drawAtPoint:NSMakePoint(5, self.bounds.size.height - 35)
              withAttributes:@{
                  NSForegroundColorAttributeName : [NSColor blackColor],
                  NSFontAttributeName : [NSFont boldSystemFontOfSize:10]
              }];

    // Bottom-right corner
    NSRect bottomRightRect = NSMakeRect(self.bounds.size.width - 80, 0, 80, 40);
    [[NSColor blueColor] setFill];
    NSRectFill(bottomRightRect);

    NSString *bottomRightText = [NSString stringWithFormat:@"(%.0f,0)", self.bounds.size.width];
    [bottomRightText drawAtPoint:NSMakePoint(self.bounds.size.width - 75, 5)
                  withAttributes:@{
                      NSForegroundColorAttributeName : [NSColor whiteColor],
                      NSFontAttributeName : [NSFont boldSystemFontOfSize:10]
                  }];

    // Top-right corner
    NSRect topRightRect = NSMakeRect(self.bounds.size.width - 100, self.bounds.size.height - 40, 100, 40);
    [[NSColor purpleColor] setFill];
    NSRectFill(topRightRect);

    NSString *topRightText = [NSString stringWithFormat:@"(%.0f,%.0f)", self.bounds.size.width, self.bounds.size.height];
    [topRightText drawAtPoint:NSMakePoint(self.bounds.size.width - 95, self.bounds.size.height - 35)
               withAttributes:@{
                   NSForegroundColorAttributeName : [NSColor whiteColor],
                   NSFontAttributeName : [NSFont boldSystemFontOfSize:10]
               }];

    // Draw axes
    [[NSColor grayColor] setStroke];
    NSBezierPath *xAxis = [NSBezierPath bezierPath];
    [xAxis moveToPoint:NSMakePoint(0, 0)];
    [xAxis lineToPoint:NSMakePoint(self.bounds.size.width, 0)];
    [xAxis setLineWidth:2.0];
    [xAxis stroke];

    NSBezierPath *yAxis = [NSBezierPath bezierPath];
    [yAxis moveToPoint:NSMakePoint(0, 0)];
    [yAxis lineToPoint:NSMakePoint(0, self.bounds.size.height)];
    [yAxis setLineWidth:2.0];
    [yAxis stroke];

    // Arrow indicators for axes
    [@"X +" drawAtPoint:NSMakePoint(self.bounds.size.width - 30, 10)
         withAttributes:@{
             NSForegroundColorAttributeName : [NSColor grayColor],
             NSFontAttributeName : [NSFont boldSystemFontOfSize:14]
         }];

    [@"Y +" drawAtPoint:NSMakePoint(10, self.bounds.size.height - 25)
         withAttributes:@{
             NSForegroundColorAttributeName : [NSColor grayColor],
             NSFontAttributeName : [NSFont boldSystemFontOfSize:14]
         }];
}

#pragma mark - NSTextInputClient Protocol

static ImGuiKey ImGui_ImplOSX_KeyCodeToImGuiKey(int key_code)
{
    switch (key_code)
    {
        case kVK_ANSI_A: return ImGuiKey_A;
        case kVK_ANSI_S: return ImGuiKey_S;
        case kVK_ANSI_D: return ImGuiKey_D;
        case kVK_ANSI_F: return ImGuiKey_F;
        case kVK_ANSI_H: return ImGuiKey_H;
        case kVK_ANSI_G: return ImGuiKey_G;
        case kVK_ANSI_Z: return ImGuiKey_Z;
        case kVK_ANSI_X: return ImGuiKey_X;
        case kVK_ANSI_C: return ImGuiKey_C;
        case kVK_ANSI_V: return ImGuiKey_V;
        case kVK_ANSI_B: return ImGuiKey_B;
        case kVK_ANSI_Q: return ImGuiKey_Q;
        case kVK_ANSI_W: return ImGuiKey_W;
        case kVK_ANSI_E: return ImGuiKey_E;
        case kVK_ANSI_R: return ImGuiKey_R;
        case kVK_ANSI_Y: return ImGuiKey_Y;
        case kVK_ANSI_T: return ImGuiKey_T;
        case kVK_ANSI_1: return ImGuiKey_1;
        case kVK_ANSI_2: return ImGuiKey_2;
        case kVK_ANSI_3: return ImGuiKey_3;
        case kVK_ANSI_4: return ImGuiKey_4;
        case kVK_ANSI_6: return ImGuiKey_6;
        case kVK_ANSI_5: return ImGuiKey_5;
        case kVK_ANSI_Equal: return ImGuiKey_Equal;
        case kVK_ANSI_9: return ImGuiKey_9;
        case kVK_ANSI_7: return ImGuiKey_7;
        case kVK_ANSI_Minus: return ImGuiKey_Minus;
        case kVK_ANSI_8: return ImGuiKey_8;
        case kVK_ANSI_0: return ImGuiKey_0;
        case kVK_ANSI_RightBracket: return ImGuiKey_RightBracket;
        case kVK_ANSI_O: return ImGuiKey_O;
        case kVK_ANSI_U: return ImGuiKey_U;
        case kVK_ANSI_LeftBracket: return ImGuiKey_LeftBracket;
        case kVK_ANSI_I: return ImGuiKey_I;
        case kVK_ANSI_P: return ImGuiKey_P;
        case kVK_ANSI_L: return ImGuiKey_L;
        case kVK_ANSI_J: return ImGuiKey_J;
        case kVK_ANSI_Quote: return ImGuiKey_Apostrophe;
        case kVK_ANSI_K: return ImGuiKey_K;
        case kVK_ANSI_Semicolon: return ImGuiKey_Semicolon;
        case kVK_ANSI_Backslash: return ImGuiKey_Backslash;
        case kVK_ANSI_Comma: return ImGuiKey_Comma;
        case kVK_ANSI_Slash: return ImGuiKey_Slash;
        case kVK_ANSI_N: return ImGuiKey_N;
        case kVK_ANSI_M: return ImGuiKey_M;
        case kVK_ANSI_Period: return ImGuiKey_Period;
        case kVK_ANSI_Grave: return ImGuiKey_GraveAccent;
        case kVK_ANSI_KeypadDecimal: return ImGuiKey_KeypadDecimal;
        case kVK_ANSI_KeypadMultiply: return ImGuiKey_KeypadMultiply;
        case kVK_ANSI_KeypadPlus: return ImGuiKey_KeypadAdd;
        case kVK_ANSI_KeypadClear: return ImGuiKey_NumLock;
        case kVK_ANSI_KeypadDivide: return ImGuiKey_KeypadDivide;
        case kVK_ANSI_KeypadEnter: return ImGuiKey_KeypadEnter;
        case kVK_ANSI_KeypadMinus: return ImGuiKey_KeypadSubtract;
        case kVK_ANSI_KeypadEquals: return ImGuiKey_KeypadEqual;
        case kVK_ANSI_Keypad0: return ImGuiKey_Keypad0;
        case kVK_ANSI_Keypad1: return ImGuiKey_Keypad1;
        case kVK_ANSI_Keypad2: return ImGuiKey_Keypad2;
        case kVK_ANSI_Keypad3: return ImGuiKey_Keypad3;
        case kVK_ANSI_Keypad4: return ImGuiKey_Keypad4;
        case kVK_ANSI_Keypad5: return ImGuiKey_Keypad5;
        case kVK_ANSI_Keypad6: return ImGuiKey_Keypad6;
        case kVK_ANSI_Keypad7: return ImGuiKey_Keypad7;
        case kVK_ANSI_Keypad8: return ImGuiKey_Keypad8;
        case kVK_ANSI_Keypad9: return ImGuiKey_Keypad9;
        case kVK_Return: return ImGuiKey_Enter;
        case kVK_Tab: return ImGuiKey_Tab;
        case kVK_Space: return ImGuiKey_Space;
        case kVK_Delete: return ImGuiKey_Backspace;
        case kVK_Escape: return ImGuiKey_Escape;
        case kVK_CapsLock: return ImGuiKey_CapsLock;
        case kVK_Control: return ImGuiKey_LeftCtrl;
        case kVK_Shift: return ImGuiKey_LeftShift;
        case kVK_Option: return ImGuiKey_LeftAlt;
        case kVK_Command: return ImGuiKey_LeftSuper;
        case kVK_RightControl: return ImGuiKey_RightCtrl;
        case kVK_RightShift: return ImGuiKey_RightShift;
        case kVK_RightOption: return ImGuiKey_RightAlt;
        case kVK_RightCommand: return ImGuiKey_RightSuper;
//      case kVK_Function: return ImGuiKey_;
//      case kVK_VolumeUp: return ImGuiKey_;
//      case kVK_VolumeDown: return ImGuiKey_;
//      case kVK_Mute: return ImGuiKey_;
        case kVK_F1: return ImGuiKey_F1;
        case kVK_F2: return ImGuiKey_F2;
        case kVK_F3: return ImGuiKey_F3;
        case kVK_F4: return ImGuiKey_F4;
        case kVK_F5: return ImGuiKey_F5;
        case kVK_F6: return ImGuiKey_F6;
        case kVK_F7: return ImGuiKey_F7;
        case kVK_F8: return ImGuiKey_F8;
        case kVK_F9: return ImGuiKey_F9;
        case kVK_F10: return ImGuiKey_F10;
        case kVK_F11: return ImGuiKey_F11;
        case kVK_F12: return ImGuiKey_F12;
        case kVK_F13: return ImGuiKey_F13;
        case kVK_F14: return ImGuiKey_F14;
        case kVK_F15: return ImGuiKey_F15;
        case kVK_F16: return ImGuiKey_F16;
        case kVK_F17: return ImGuiKey_F17;
        case kVK_F18: return ImGuiKey_F18;
        case kVK_F19: return ImGuiKey_F19;
        case kVK_F20: return ImGuiKey_F20;
        case 0x6E: return ImGuiKey_Menu;
        case kVK_Help: return ImGuiKey_Insert;
        case kVK_Home: return ImGuiKey_Home;
        case kVK_PageUp: return ImGuiKey_PageUp;
        case kVK_ForwardDelete: return ImGuiKey_Delete;
        case kVK_End: return ImGuiKey_End;
        case kVK_PageDown: return ImGuiKey_PageDown;
        case kVK_LeftArrow: return ImGuiKey_LeftArrow;
        case kVK_RightArrow: return ImGuiKey_RightArrow;
        case kVK_DownArrow: return ImGuiKey_DownArrow;
        case kVK_UpArrow: return ImGuiKey_UpArrow;
        default: return ImGuiKey_None;
    }
}

// Must only be called for a mouse event, otherwise an exception occurs
// (Note that NSEventTypeScrollWheel is considered "other input". Oddly enough an exception does not occur with it, but the value will sometimes be wrong!)
static ImGuiMouseSource GetMouseSource(NSEvent* event)
{
    switch (event.subtype)
    {
        case NSEventSubtypeTabletPoint:
            return ImGuiMouseSource_Pen;
        // macOS considers input from relative touch devices (like the trackpad or Apple Magic Mouse) to be touch input.
        // This doesn't really make sense for Dear ImGui, which expects absolute touch devices only.
        // There does not seem to be a simple way to disambiguate things here so we consider NSEventSubtypeTouch events to always come from mice.
        // See https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html#//apple_ref/doc/uid/10000060i-CH13-SW24
        //case NSEventSubtypeTouch:
        //    return ImGuiMouseSource_TouchScreen;
        case NSEventSubtypeMouseEvent:
        default:
            return ImGuiMouseSource_Mouse;
    }
}

static bool ImGui_ImplOSX_HandleEvent(NSEvent* event, NSView* view)
{
    // Only process events from the window containing ImGui view
    if (event.window != view.window)
        return false;
    ImGuiIO& io = ImGui::GetIO();

    if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown || event.type == NSEventTypeOtherMouseDown)
    {
        int button = (int)[event buttonNumber];
        if (button >= 0 && button < ImGuiMouseButton_COUNT)
        {
            io.AddMouseSourceEvent(GetMouseSource(event));
            io.AddMouseButtonEvent(button, true);
        }
        return io.WantCaptureMouse;
    }

    if (event.type == NSEventTypeLeftMouseUp || event.type == NSEventTypeRightMouseUp || event.type == NSEventTypeOtherMouseUp)
    {
        int button = (int)[event buttonNumber];
        if (button >= 0 && button < ImGuiMouseButton_COUNT)
        {
            io.AddMouseSourceEvent(GetMouseSource(event));
            io.AddMouseButtonEvent(button, false);
        }
        return io.WantCaptureMouse;
    }

    if (event.type == NSEventTypeMouseMoved || event.type == NSEventTypeLeftMouseDragged || event.type == NSEventTypeRightMouseDragged || event.type == NSEventTypeOtherMouseDragged)
    {
        NSPoint mousePoint = event.locationInWindow;
        if (event.window == nil)
            mousePoint = [[view window] convertPointFromScreen:mousePoint];
        mousePoint = [view convertPoint:mousePoint fromView:nil];
        if ([view isFlipped])
            mousePoint = NSMakePoint(mousePoint.x, mousePoint.y);
        else
            mousePoint = NSMakePoint(mousePoint.x, view.bounds.size.height - mousePoint.y);
        io.AddMouseSourceEvent(GetMouseSource(event));
        io.AddMousePosEvent((float)mousePoint.x, (float)mousePoint.y);
        return io.WantCaptureMouse;
    }

    if (event.type == NSEventTypeScrollWheel)
    {
        // Ignore canceled events.
        //
        // From macOS 12.1, scrolling with two fingers and then decelerating
        // by tapping two fingers results in two events appearing:
        //
        // 1. A scroll wheel NSEvent, with a phase == NSEventPhaseMayBegin, when the user taps
        // two fingers to decelerate or stop the scroll events.
        //
        // 2. A scroll wheel NSEvent, with a phase == NSEventPhaseCancelled, when the user releases the
        // two-finger tap. It is this event that sometimes contains large values for scrollingDeltaX and
        // scrollingDeltaY. When these are added to the current x and y positions of the scrolling view,
        // it appears to jump up or down. It can be observed in Preview, various JetBrains IDEs and here.
        if (event.phase == NSEventPhaseCancelled)
            return false;

        double wheel_dx = 0.0;
        double wheel_dy = 0.0;

        #if MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
        if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6)
        {
            wheel_dx = [event scrollingDeltaX];
            wheel_dy = [event scrollingDeltaY];
            if ([event hasPreciseScrollingDeltas])
            {
                wheel_dx *= 0.01;
                wheel_dy *= 0.01;
            }
        }
        else
        #endif // MAC_OS_X_VERSION_MAX_ALLOWED
        {
            wheel_dx = [event deltaX] * 0.1;
            wheel_dy = [event deltaY] * 0.1;
        }
        if (wheel_dx != 0.0 || wheel_dy != 0.0)
            io.AddMouseWheelEvent((float)wheel_dx, (float)wheel_dy);

        return io.WantCaptureMouse;
    }

    if (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp)
    {
        if ([event isARepeat])
            return io.WantCaptureKeyboard;

        int key_code = (int)[event keyCode];
        ImGuiKey key = ImGui_ImplOSX_KeyCodeToImGuiKey(key_code);
        io.AddKeyEvent(key, event.type == NSEventTypeKeyDown);
        io.SetKeyEventNativeData(key, key_code, -1); // To support legacy indexing (<1.87 user code)

        return io.WantCaptureKeyboard;
    }

    if (event.type == NSEventTypeFlagsChanged)
    {
        unsigned short key_code = [event keyCode];
        NSEventModifierFlags modifier_flags = [event modifierFlags];

        io.AddKeyEvent(ImGuiMod_Shift, (modifier_flags & NSEventModifierFlagShift)   != 0);
        io.AddKeyEvent(ImGuiMod_Ctrl,  (modifier_flags & NSEventModifierFlagControl) != 0);
        io.AddKeyEvent(ImGuiMod_Alt,   (modifier_flags & NSEventModifierFlagOption)  != 0);
        io.AddKeyEvent(ImGuiMod_Super, (modifier_flags & NSEventModifierFlagCommand) != 0);

        ImGuiKey key = ImGui_ImplOSX_KeyCodeToImGuiKey(key_code);
        if (key != ImGuiKey_None)
        {
            // macOS does not generate down/up event for modifiers. We're trying
            // to use hardware dependent masks to extract that information.
            // 'imgui_mask' is left as a fallback.
            NSEventModifierFlags mask = 0;
            switch (key)
            {
                case ImGuiKey_LeftCtrl:   mask = 0x0001; break;
                case ImGuiKey_RightCtrl:  mask = 0x2000; break;
                case ImGuiKey_LeftShift:  mask = 0x0002; break;
                case ImGuiKey_RightShift: mask = 0x0004; break;
                case ImGuiKey_LeftSuper:  mask = 0x0008; break;
                case ImGuiKey_RightSuper: mask = 0x0010; break;
                case ImGuiKey_LeftAlt:    mask = 0x0020; break;
                case ImGuiKey_RightAlt:   mask = 0x0040; break;
                default:
                    return io.WantCaptureKeyboard;
            }
            io.AddKeyEvent(key, (modifier_flags & mask) != 0);
            io.SetKeyEventNativeData(key, key_code, -1); // To support legacy indexing (<1.87 user code)
        }

        return io.WantCaptureKeyboard;
    }

    return false;
}


- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    NSString *text = [string isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)string string] : (NSString *)string;

    NSLog(@"Insert text: '%@'", text);

    // If CEF doesn't have focus, this text input is for ImGui
    if (!shouldHandleKeyEvents)
    {
        ImGuiIO &io = ImGui::GetIO();

        NSString *characters;
        if ([string isKindOfClass:[NSAttributedString class]])
            characters = [string string];
        else
            characters = (NSString *)string;

        io.AddInputCharactersUTF8(characters.UTF8String);
    }

    // Replace any marked text
    if (_hasMarkedText)
    {
        [self unmarkText];
    }

    // Insert the text
    [_textBuffer appendString:text];
    self.inputText = [_textBuffer copy];

    // If we are handling a key down event then ImeCommitText() will be called from the keyEvent: method
    if (_handlingKeyDown)
    {
        _textToBeInserted.append([text UTF8String]);
    }
    else
    {
        CefRange range = {static_cast<uint32_t>(replacementRange.location),
                          static_cast<uint32_t>(NSMaxRange(replacementRange))};
        _app->inject_ime_commit_text([text UTF8String], range, 0);
    }

    [self setNeedsDisplay:YES];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange
{
    NSAttributedString *markedText = [string isKindOfClass:[NSAttributedString class]] ? (NSAttributedString *)string : [[NSAttributedString alloc] initWithString:(NSString *)string];

    NSLog(@"Set marked text: '%@'", markedText.string);

    self.markedText = markedText;
    _markedRange = NSMakeRange([_textBuffer length], [markedText.string length]);
    _selectedRange = selectedRange;
    NSString *plain = markedText.string ?: @"";
    _markedTextString = [plain copy];
    _hasMarkedText = plain.length > 0;

    _markedTextAttributed = markedText;

    // Extract underlines if it's an attributed string
    if ([string isKindOfClass:[NSAttributedString class]])
    {
        [self extractUnderlines:(NSAttributedString *)string];
    }
    else
    {
        // Use a thin black underline by default
        _underlines.clear();
        cef_composition_underline_t line = {
            sizeof(cef_composition_underline_t),
            {0, static_cast<uint32_t>([markedText.string length])},
            0xFF000000, // Black
            0,
            false};
        _underlines.push_back(line);
    }

    // If we are handling a key down event then ImeSetComposition() will be called from the keyEvent: method
    if (_handlingKeyDown)
    {
        _setMarkedTextReplacementRange = CefRange(static_cast<uint32_t>(replacementRange.location),
                                                  static_cast<uint32_t>(NSMaxRange(replacementRange)));
    }
    else
    {
        CefRange replacement_range(static_cast<uint32_t>(replacementRange.location),
                                   static_cast<uint32_t>(NSMaxRange(replacementRange)));
        CefRange selection_range(static_cast<uint32_t>(selectedRange.location),
                                 static_cast<uint32_t>(NSMaxRange(selectedRange)));

        _app->inject_ime_set_composition([_markedTextString UTF8String], _underlines,
                                         replacement_range, selection_range);
    }

    [self setNeedsDisplay:YES];
}

- (void)unmarkText
{
    NSLog(@"Unmark text");

    if (_hasMarkedText && _markedTextString)
    {
        [_textBuffer appendString:_markedTextString];
        self.inputText = [_textBuffer copy];
    }

    self.markedText = nil;
    _markedTextString = nil;
    _markedTextAttributed = nil;
    _markedRange = NSMakeRange(NSNotFound, 0);
    _hasMarkedText = NO;
    _underlines.clear();

    // If we are handling a key down event then ImeFinishComposingText() will be called from the keyEvent: method
    if (!_handlingKeyDown)
    {
        _app->inject_ime_finish_composing_text(false);
    }
    else
    {
        _unmarkTextCalled = YES;
    }

    [self setNeedsDisplay:YES];
}

- (NSRange)selectedRange
{
    return _selectedRange;
}

- (NSRange)markedRange
{
    return _markedRange;
}

- (BOOL)hasMarkedText
{
    return _hasMarkedText;
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange
{
    // Return attributed substring for the range
    if (actualRange)
    {
        *actualRange = range;
    }

    NSString *fullText;
    if (_hasMarkedText && _markedTextString)
    {
        fullText = [_textBuffer stringByAppendingString:_markedTextString];
    }
    else
    {
        fullText = [_textBuffer copy];
    }

    if (range.location >= [fullText length])
    {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    NSRange clampedRange = NSIntersectionRange(range, NSMakeRange(0, [fullText length]));
    NSString *substring = [fullText substringWithRange:clampedRange];

    return [[NSAttributedString alloc] initWithString:substring];
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText
{
    return @[ NSUnderlineStyleAttributeName, NSForegroundColorAttributeName ];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange
{
    // Choose position based on followMouse setting
    NSPoint basePosition;

    if (self.followMouse)
    {
        basePosition = self.lastMousePosition;
    }
    else
    {
        basePosition = self.textCursorPosition;
    }

    // Offset the IME window slightly above and to the right of the cursor
    NSPoint imePosition = NSMakePoint(basePosition.x + 5, basePosition.y + 25);

    // Make sure the IME window stays within view bounds
    CGFloat imeWidth = 200;
    CGFloat imeHeight = 20;

    // Adjust horizontal position if it would go off the right edge
    if (imePosition.x + imeWidth > self.bounds.size.width)
    {
        imePosition.x = self.bounds.size.width - imeWidth - 10;
    }

    // Adjust vertical position if it would go off the top edge
    if (imePosition.y + imeHeight > self.bounds.size.height)
    {
        imePosition.y = basePosition.y - imeHeight - 5; // Position below cursor instead
    }

    // Make sure it doesn't go below the bottom edge
    if (imePosition.y < 0)
    {
        imePosition.y = 10;
    }

    NSRect rect = NSMakeRect(imePosition.x, imePosition.y, imeWidth, imeHeight);

    // Convert to window coordinates, then screen coordinates
    NSRect windowRect = [self convertRect:rect toView:nil];
    NSRect screenRect = [self.window convertRectToScreen:windowRect];

    if (actualRange)
    {
        *actualRange = range;
    }

    // NSLog(@"IME window positioned at: (%.1f, %.1f) in screen coordinates", screenRect.origin.x, screenRect.origin.y);

    return screenRect;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
    // Convert point to character index
    return [_textBuffer length];
}

// Edit menu support methods
- (void)undo
{
    if (_app)
    {
        _app->undo();
    }
}

- (void)redo
{
    if (_app)
    {
        _app->redo();
    }
}

- (void)cut
{
    if (_app)
    {
        _app->cut();
    }
}

- (void)copy
{
    std::cout << "Copy called from Edit menu" << std::endl;
    if (_app)
    {
        _app->copy();
    }
}

- (void)paste
{
    if (_app)
    {
        _app->paste();
    }
}

- (void)selectAll
{
    if (_app)
    {
        _app->select_all();
    }
}

@end
