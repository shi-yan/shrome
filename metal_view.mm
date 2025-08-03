#import "metal_view.h"

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/cef_command_line.h" // Required for CefCommandLine
#include "mycef.h"

@interface MainMetalView () {
    CefRefPtr<MyApp> _app;
}

@end

@implementation MainMetalView
{
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    NSMutableString *_textBuffer;
    BOOL _hasMarkedText;
}

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device
{
    self = [super initWithFrame:frame device:device];
    if (self)
    {
        // Enable drawing to work with Metal
        self.device = device;
        self.enableSetNeedsDisplay = NO;
        self.paused = NO;
        self.framebufferOnly = NO;
        self.delegate = self;
        [self setupMetal];
        [self setupTextInput];
        // Force initial display
        //[self setNeedsDisplay:YES];

        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        ImGuiIO &io = ImGui::GetIO();
        (void)io;
        io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
        // io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls

        // Setup Dear ImGui style
        ImGui::StyleColorsDark();
        // ImGui::StyleColorsLight();

        // Setup Renderer backend
        ImGui_ImplMetal_Init(device);
        ImGui_ImplOSX_Init(self);

        [self setupCEF]; // Initialize CEF
        CGFloat pixelDensity = [self.window backingScaleFactor];
        int normalWinWidth = frame.size.width;
        int normalWinHeight = frame.size.height;

        _app = new MyApp((__bridge MTL::Device *)self.device, normalWinWidth, normalWinHeight, pixelDensity);
        _app->init((__bridge MTL::Device *)self.device, MTLPixelFormatBGRA8Unorm, normalWinWidth, normalWinHeight);
    }
    return self;
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

- (void)setupMetal
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

- (void)dealloc
{
    _app->close(true);

    while (!_app->is_browser_closed())
    {
        CefDoMessageLoopWork(); // Or sleep a bit i
    }
    CefQuitMessageLoop();
    _app.reset();
    // Cleanup
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplOSX_Shutdown();
    ImGui::DestroyContext();
}

// MTKViewDelegate method - called automatically every frame
- (void)drawInMTKView:(MTKView *)view
{

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
        [renderEncoder setRenderPipelineState:_pipelineState];
        // Draw triangle (3 vertices) + coordinate indicators (24 vertices) = 27 total
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:27];

        // [commandBuffer commit];

        // NSLog(@"MTKView drawInMTKView called - rendering Metal content");

        // Start the Dear ImGui frame
        ImGui_ImplMetal_NewFrame(renderPassDescriptor);
        ImGui_ImplOSX_NewFrame(view);
        ImGui::NewFrame();

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
    }
}

// MTKViewDelegate method - called when view size changes
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    NSLog(@"MTKView size changed to: %.0f x %.0f", size.width, size.height);
    // Update any size-dependent resources here (like viewport, projection matrix, etc.)
}

#pragma mark - Event Handling

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    // Handle special keys for IME positioning control
    //  NSString *characters = [event charactersIgnoringModifiers];
    /*
        if ([characters isEqualToString:@"t"] || [characters isEqualToString:@"T"])
        {
            [self toggleMouseFollowing];
            return;
        }

        if ([characters isEqualToString:@"c"] || [characters isEqualToString:@"C"])
        {
            // Center the cursor
            NSPoint center = NSMakePoint(self.bounds.size.width / 2, self.bounds.size.height / 2);
            [self setCursorPosition:center];
            return;
        }

        if ([characters isEqualToString:@"r"] || [characters isEqualToString:@"R"])
        {
            // Random position
            NSPoint random = NSMakePoint(
                arc4random_uniform((uint32_t)self.bounds.size.width),
                arc4random_uniform((uint32_t)self.bounds.size.height));
            [self setCursorPosition:random];
            return;
        }

        if ([characters isEqualToString:@"d"] || [characters isEqualToString:@"D"])
        {
            // Force redraw to show coordinate indicators
            [self setNeedsDisplay:YES];
            NSLog(@"Force redraw triggered - coordinate indicators should be visible now");
            return;
        }
    */
    // Let the input method system handle this
    [self interpretKeyEvents:@[ event ]];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];

    // Update cursor position to mouse click location
    self.textCursorPosition = locationInView;
    self.lastMousePosition = locationInView;

    NSLog(@"Text cursor moved to: (%.1f, %.1f)", locationInView.x, locationInView.y);
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event
{
    if (self.followMouse)
    {
        NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];
        self.lastMousePosition = locationInView;
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

    [self setNeedsDisplay:YES];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange
{
    NSAttributedString *markedText = [string isKindOfClass:[NSAttributedString class]] ? (NSAttributedString *)string : [[NSAttributedString alloc] initWithString:(NSString *)string];

    NSLog(@"Set marked text: '%@'", markedText.string);

    self.markedText = markedText;
    _markedRange = NSMakeRange([_textBuffer length], [markedText.string length]);
    _selectedRange = selectedRange;
    _hasMarkedText = [markedText.string length] > 0;

    [self setNeedsDisplay:YES];
}

- (void)unmarkText
{
    NSLog(@"Unmark text");

    if (_hasMarkedText && _markedText)
    {
        [_textBuffer appendString:_markedText.string];
        self.inputText = [_textBuffer copy];
    }

    self.markedText = nil;
    _markedRange = NSMakeRange(NSNotFound, 0);
    _hasMarkedText = NO;

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

    NSString *fullText = _hasMarkedText ? [_textBuffer stringByAppendingString:_markedText.string] : _textBuffer;

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

    NSLog(@"IME window positioned at: (%.1f, %.1f) in screen coordinates", screenRect.origin.x, screenRect.origin.y);

    return screenRect;
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
    // Convert point to character index
    return [_textBuffer length];
}

@end
