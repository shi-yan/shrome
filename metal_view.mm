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
#include "mycef.h"
#include <simd/simd.h>

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
+ (instancetype) sharedManager;
- (void) registerApp: (CefRefPtr<MyApp>)app;
- (void) unregisterApp: (CefRefPtr<MyApp>)app;
- (void) shutdownIfAllClosed;
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

@implementation CEFManager {
    NSMutableArray *_activeApps;
}

+ (instancetype) sharedManager {
    static CEFManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[CEFManager alloc] init];
    });
    return sharedInstance;
}

-(instancetype) init {
    self = [super init];
    if (self) {
        _activeApps = [[NSMutableArray alloc] init];

    }
    return self;
}

- (void) registerApp: (CefRefPtr<MyApp>) app {
    @synchronized(self) {
        NSValue *appValue = [NSValue valueWithPointer: app.get()];
        [_activeApps addObject: appValue];
        NSLog(@"CEF app registered. Active count: %lu", (unsigned long)_activeApps.count);
    }
}

- (void)unregisterApp: (CefRefPtr<MyApp>)app {
    @synchronized(self) {
        NSValue *appValue = [NSValue valueWithPointer: app.get()];
        [_activeApps removeObject: appValue];
        NSLog(@"CEF app unregistered. Active count: %lu", (unsigned long)_activeApps.count);

        if (_activeApps.count == 0) {
            NSLog(@"All CEF apps closed, quitting message loop");
            CefQuitMessageLoop();
        }
    }
}

- (void) shutdownIfAllClosed {
    @synchronized(self) {
        if (_activeApps.count == 0) {
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

        [[CEFManager sharedManager] registerApp: _app];

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
    int exit_code = CefExecuteProcess(main_args, _app.get(), nullptr);
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

- (void) cleanup {
    NSLog(@"MainMetalView cleanup called");

    if (_app ){
        _app->close(true);
        int timeout = 100;
        while (!_app->is_browser_closed() && timeout > 0)
        {
            CefDoMessageLoopWork(); // Or sleep a bit i
            [NSThread sleepForTimeInterval:0.1];
            timeout--;
        }

        if (timeout <=0) {
            NSLog(@"Warning: Browser close timeout reached");
        }

        [[CEFManager sharedManager] unregisterApp: _app];
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
        static ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

        // 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
        if (show_demo_window)
            ImGui::ShowDemoWindow(&show_demo_window);

        // 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
        {
            static float f = 0.0f;
            static int counter = 0;

            ImGui::Begin("Hello, world!"); // Create a window called "Hello, world!" and append into it.

            ImGui::Text("This is some useful text.");          // Display some text (you can use a format strings too)
            ImGui::Checkbox("Demo Window", &show_demo_window); // Edit bools storing our window open/close state
            ImGui::Checkbox("Another Window", &show_another_window);

            ImGui::SliderFloat("float", &f, 0.0f, 1.0f);             // Edit 1 float using a slider from 0.0f to 1.0f
            ImGui::ColorEdit3("clear color", (float *)&clear_color); // Edit 3 floats representing a color

            if (ImGui::Button("Button")) // Buttons return true when clicked (most widgets return true when edited/activated)
                counter++;
            ImGui::SameLine();
            ImGui::Text("counter = %d", counter);

            ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / io.Framerate, io.Framerate);
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
        }
        else
        {
            shouldHandleMouseEvents = false;
        }

        // This is a common pattern to check for focus
        if (ImGui::IsWindowFocused(ImGuiFocusedFlags_RootAndChildWindows))
        {
            shouldHandleKeyEvents = true;
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

        // Display the framebuffer texture
        ImTextureID myFramebufferTextureID = reinterpret_cast<ImTextureID>(_app->m_texture);
        ImGui::Image(myFramebufferTextureID, contentSize, ImVec2(0, 0), ImVec2(1, 1));
        ImGui::End();

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

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    if ([event modifierFlags] & NSEventModifierFlagCommand)
    {
        NSString *characters = [event charactersIgnoringModifiers];

        if ([characters isEqualToString:@"c"])
        {
            // Handle Copy
            [self handleCopy];
            return YES;
        }
        else if ([characters isEqualToString:@"v"])
        {
            // Handle Paste
            [self handlePaste];
            return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

- (void)handleCopy
{
    // Get selected text from CEF
}

- (void)handlePaste
{
    // Get pasteboard content and paste into CEF
}

- (void)keyDown:(NSEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();
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
    }
}

- (void)keyUp:(NSEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();
    if (io.WantCaptureKeyboard && shouldHandleKeyEvents)
    {
        CefKeyEvent keyEvent;
        [self getKeyEvent:keyEvent forEvent:event];
        keyEvent.type = KEYEVENT_KEYUP;

        _app->inject_key_event(keyEvent);
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
        mouseEvent.modifiers = [self convertModifiers:[event modifierFlags]];

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
        mouseEvent.modifiers = [self convertModifiers:[event modifierFlags]];

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
        mouseEvent.modifiers = [self convertModifiers:[event modifierFlags]];

        int deltaX = static_cast<int>([event scrollingDeltaX]);
        int deltaY = static_cast<int>([event scrollingDeltaY]);

        _app->inject_mouse_wheel(mouseEvent, deltaX, deltaY);

        // NSLog(@"mouse scroll at (%.1f, %.1f) with delta (%d, %d)  (%f, %f)",
        //       locationInView.x, locationInView.y, deltaX, deltaY, [event scrollingDeltaX], [event scrollingDeltaY]);
    }
}

// Helper method to convert AppKit modifier flags to CEF modifier flags
- (uint32_t)convertModifiers:(NSUInteger)appKitModifiers
{
    uint32_t cefModifiers = 0;

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
    keyEvent.modifiers = [self convertModifiers:[event modifierFlags]];
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
    if (shouldHandleMouseEvents == true)
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
        // std::cout << "mouse motion " << mouseEvent.x << ", " << mouseEvent.y << std::endl;
        mouseEvent.modifiers = [self convertModifiers:[event modifierFlags]];

        _app->inject_mouse_motion(mouseEvent);
    }
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

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    NSString *text = [string isKindOfClass:[NSAttributedString class]] ? [(NSAttributedString *)string string] : (NSString *)string;

    NSLog(@"Insert text: '%@'", text);

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
- (void)undo {
    if (_app) {
        _app->undo();
    }
}

- (void)redo {
    if (_app) {
        _app->redo();
    }
}

- (void)cut {
    if (_app) {
        _app->cut();
    }
}

- (void)copy {
    if (_app) {
        _app->copy();
    }
}

- (void)paste {
    if (_app) {
        _app->paste();
    }
}

- (void)selectAll {
    if (_app) {
        _app->select_all();
    }
}

@end
