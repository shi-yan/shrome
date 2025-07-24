// Dear ImGui: standalone example application for SDL2 + Metal
// (SDL is a cross-platform general purpose library for handling windows, inputs, OpenGL/Vulkan/Metal graphics context creation, etc.)

// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

#include "imgui.h"
#include "imgui_impl_sdl3.h"
#include "imgui_impl_metal.h"
#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/cef_command_line.h" // Required for CefCommandLine

#include <iostream>
#include <SDL3/SDL.h>

#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <simd/simd.h>
#include <sstream>
#include "mycef.h"
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/gtc/constants.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/ext/matrix_relational.hpp>
#include <glm/ext/vector_relational.hpp>
#include <glm/ext/scalar_relational.hpp>
#include <glm/ext/vector_float2.hpp>   // vec2
#include <glm/ext/vector_float3.hpp>   // vec3
#include <glm/ext/matrix_float4x4.hpp> // mat4x4
#include <glm/glm.hpp>
#include <glm/gtx/string_cast.hpp>

int main(int argc, char **argv)
{

    // Load the CEF library. This is required for macOS.
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInMain())
    {
        return 1;
    }

    CefMainArgs main_args(argc, argv);

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD))
    {
        printf("Error: SDL_Init(): %s\n", SDL_GetError());
        return -1;
    }

    float main_scale = SDL_GetDisplayContentScale(SDL_GetPrimaryDisplay());
    SDL_WindowFlags window_flags = SDL_WINDOW_METAL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN | SDL_WINDOW_HIGH_PIXEL_DENSITY;
    int prevWinWidth = 1280 * main_scale;
    int prevWinHeight = 720 * main_scale;
    SDL_Window *window = SDL_CreateWindow("Dear ImGui SDL3+SDL_GPU example", (int)(prevWinWidth), (int)(prevWinHeight), window_flags);
    if (window == nullptr)
    {
        printf("Error: SDL_CreateWindow(): %s\n", SDL_GetError());
        return -1;
    }
    SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
    SDL_ShowWindow(window);

    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;  // Enable Gamepad Controls

    // Setup Dear ImGui style
    ImGui::StyleColorsDark();
    // ImGui::StyleColorsLight();

    // Setup scaling
    ImGuiStyle &style = ImGui::GetStyle();
    style.ScaleAllSizes(main_scale); // Bake a fixed style scale. (until we have a solution for dynamic style scaling, changing this requires resetting Style + calling this again)
    style.FontScaleDpi = main_scale; // Set initial font scale. (using io.ConfigDpiScaleFonts=true makes this unnecessary. We leave both here for documentation purpose)

    MTL::Device *metal_device = MTL::CreateSystemDefaultDevice();
    if (!metal_device)
    {
        printf("Error: failed to create Metal device.\n");
        SDL_DestroyWindow(window);
        SDL_Quit();
        return -1;
    }

    SDL_MetalView view = SDL_Metal_CreateView(window);
    CA::MetalLayer *layer = (CA::MetalLayer *)SDL_Metal_GetLayer(view);
    layer->setDevice(metal_device);
    layer->setPixelFormat(MTL::PixelFormat::PixelFormatBGRA8Unorm);
    ImGui_ImplMetal_Init((__bridge id<MTLDevice>)layer->device());

    ImGui_ImplSDL3_InitForMetal(window);
    SDL_GetWindowSizeInPixels(window, &prevWinWidth, &prevWinHeight);
    int normalWinWidth, normalWinHeight;
    SDL_GetWindowSize(window, &normalWinWidth, &normalWinHeight);
    int pixelDensity = prevWinWidth / normalWinWidth;
    std::cout << "prevWinWidth" << prevWinWidth << ", " << prevWinHeight << std::endl;
    CefRefPtr<MyApp> app(new MyApp(layer->device(), normalWinWidth, normalWinHeight, pixelDensity));
    app->init(layer->device(), MTL::PixelFormat::PixelFormatBGRA8Unorm, prevWinWidth, prevWinHeight);
    // CEF's multi-process architecture requires CefExecuteProcess to be called
    // early in the application's entry point. [6, 7]
    // If it returns a value other than -1, a sub-process was handled, and the
    // application should exit.
    int exit_code = CefExecuteProcess(main_args, app.get(), nullptr);
    if (exit_code >= 0)
    {
        // The sub-process has exited, so the main process should also exit.
        return exit_code;
    }

    CefSettings settings;
    // Required for windowless (offscreen) rendering. Must be set before CefInitialize. [3, 1]
    settings.windowless_rendering_enabled = true;

#if !defined(CEF_USE_SANDBOX)
    // Required if you're not using the sandbox. For simplicity in a minimal
    // example, disabling the sandbox is common.
    settings.no_sandbox = true;
#endif

    // If you need to specify a cache path for performance or storage
    // CefString(&settings.cache_path) = "cef_cache";

    if (!CefInitialize(main_args, settings, app.get(), nullptr))
    { // [1]
        return CefGetExitCode();
    }

    MTL::Buffer *projection_buffer = layer->device()->newBuffer(sizeof(simd::float4x4), MTL::ResourceStorageModeShared);

    MTL::CommandQueue *commandQueue = layer->device()->newCommandQueue();
    MTL::RenderPassDescriptor *renderPassDescriptor = MTL::RenderPassDescriptor::renderPassDescriptor();

    // Our state
    bool show_demo_window = false;
    bool show_text_objects = false;
    bool show_char_objects = false;
    bool show_another_window = false;

    float clear_color[4] = {0.45f, 0.55f, 0.60f, 1.00f};

    // Main loop
    bool done = false;

    // float prevX = 0;
    // float prevY = 0;
    enum class DraggingType
    {
        None,
        Pan,
        Select
    };

    DraggingType isDragging = DraggingType::None;
    MTL::Texture *depthTexture = nullptr;
    bool isLeftButtonDown = false;
    bool isRightButtonDown = false;
    bool isMiddleButtonDown = false;
    // bool over_a_char = false;
    while (!done)
    {
        {
            bool windowSizeDirty = false;
            int winWidth, winHeight;
            // int renderOutputWidth, renderOutputHeight;
            SDL_GetWindowSizeInPixels(window, &winWidth, &winHeight);

            if (winWidth != prevWinWidth || winHeight != prevWinHeight)
            {
                windowSizeDirty = true;
                prevWinWidth = winWidth;
                prevWinHeight = winHeight;
            }

            ImGui::SetMouseCursor(app->get_cursor_type());

            SDL_Event event;
            while (SDL_PollEvent(&event))
            {
                ImGui_ImplSDL3_ProcessEvent(&event);
                if (event.type == SDL_EVENT_QUIT)
                {
                    done = true;
                }
                else if (event.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED && event.window.windowID == SDL_GetWindowID(window))
                {
                    done = true;
                }
                else if (event.type == SDL_EVENT_MOUSE_BUTTON_DOWN)
                {
                    if (!io.WantCaptureMouse)
                    {
                        // std::cout << "mouse button " << ((int)event.button.button) << std::endl;

                        CefMouseEvent mouse_event;
                        mouse_event.x = event.button.x * pixelDensity - 0;
                        mouse_event.y = event.button.y * pixelDensity - 0;
                        mouse_event.modifiers = 0; // Set appropriate modifiers

                        CefBrowserHost::MouseButtonType btn_type;
                        if (event.button.button == SDL_BUTTON_LEFT)
                        {
                            btn_type = MBT_LEFT;
                            isLeftButtonDown = true;
                            mouse_event.modifiers = EVENTFLAG_LEFT_MOUSE_BUTTON;
                        }
                        else if (event.button.button == SDL_BUTTON_RIGHT)
                        {
                            btn_type = MBT_RIGHT;
                            isRightButtonDown = true;
                            mouse_event.modifiers = EVENTFLAG_RIGHT_MOUSE_BUTTON;
                        }
                        else if (event.button.button == SDL_BUTTON_MIDDLE)
                        {
                            isMiddleButtonDown = true;
                            mouse_event.modifiers = EVENTFLAG_MIDDLE_MOUSE_BUTTON;
                            btn_type = MBT_MIDDLE;
                        }
                        else
                            break; // Ignore other buttons
                        // std::cout << "injected mouse up down 2"  << std::endl;
                        app->inject_mouse_up_down(mouse_event, btn_type, false, 1);
                    }
                }
                else if (event.type == SDL_EVENT_MOUSE_MOTION /*&& isDragging != DraggingType::None*/)
                {
                    if (!io.WantCaptureMouse)
                    {
                        CefMouseEvent mouse_event;
                        // Convert SDL screen coords to CEF view coords
                        mouse_event.x = event.motion.x * pixelDensity;
                        mouse_event.y = event.motion.y * pixelDensity;
                        mouse_event.modifiers = 0; // Set appropriate modifiers (shift, ctrl, alt)
                        if (isLeftButtonDown)
                            mouse_event.modifiers |= EVENTFLAG_LEFT_MOUSE_BUTTON;
                        if (isRightButtonDown)
                            mouse_event.modifiers |= EVENTFLAG_RIGHT_MOUSE_BUTTON;
                        if (isMiddleButtonDown)
                            mouse_event.modifiers |= EVENTFLAG_MIDDLE_MOUSE_BUTTON;
                        if (isDragging == DraggingType::Pan)
                        {
                            // Sint32 currMouseX = event.motion.x;
                            // Sint32 currMouseY = event.motion.y;

                            // prevX = currMouseX;
                            // prevY = currMouseY;
                        }
                        else if (isDragging == DraggingType::None)
                        {
                            //  float currMouseX = event.motion.x * scale_x;
                            //  float currMouseY = event.motion.y * scale_y;
                        }

                        app->inject_mouse_motion(mouse_event);
                    }
                }
                else if (event.type == SDL_EVENT_MOUSE_BUTTON_UP)
                {
                    if (!io.WantCaptureMouse)
                    {
                        isDragging = DraggingType::None;

                        CefMouseEvent mouse_event;
                        mouse_event.x = event.button.x * pixelDensity - 0;
                        mouse_event.y = event.button.y * pixelDensity - 0;
                        mouse_event.modifiers = 0; // Set appropriate modifiers

                        CefBrowserHost::MouseButtonType btn_type;
                        if (event.button.button == SDL_BUTTON_LEFT)
                            btn_type = MBT_LEFT;
                        else if (event.button.button == SDL_BUTTON_RIGHT)
                            btn_type = MBT_RIGHT;
                        else if (event.button.button == SDL_BUTTON_MIDDLE)
                            btn_type = MBT_MIDDLE;
                        else
                            break; // Ignore other buttons

                        app->inject_mouse_up_down(mouse_event, btn_type, true, 1);
                    }
                }
                else if (event.type == SDL_EVENT_MOUSE_WHEEL)
                {

                    CefMouseEvent mouse_event;
                    // You'll need current mouse X/Y for wheel event, SDL_MouseWheelEvent doesn't provide it
                    float mouse_x, mouse_y;
                    SDL_GetMouseState(&mouse_x, &mouse_y);
                    mouse_event.x = mouse_x - 0;
                    mouse_event.y = mouse_y - 0;
                    mouse_event.modifiers = 0;
                    app->inject_mouse_wheel(mouse_event, event.wheel.x * 10, event.wheel.y * 10); // Adjust sensitivit
                }
                else if (event.type == SDL_EVENT_TEXT_INPUT)
                { // For typed characters
                    if (!io.WantCaptureKeyboard)
                    {
                        // 1. Get the UTF-8 input text from SDL
                        const char *utf8_text = event.text.text;

                        // 2. Convert to CefString (which internallly handles UTF-8 to UTF-16 conversion on construction).
                        // Since CefKeyEvent::character is char16, we need CefStringUTF16 for direct access.
                        CefStringUTF16 cef_text_utf16 = utf8_text;

                        // 3. Access the internal UTF-16 buffer directly from the underlying struct_type
                        // GetWritableStruct() ensures the internal string_ is allocated.
                        const char16_t *utf16_data = cef_text_utf16.c_str(); // <--- THIS IS THE CORRECT METHOD NOW!
                        size_t utf16_length = cef_text_utf16.length();

                        if (utf16_data && utf16_length > 0)
                        {
                            for (size_t i = 0; i < utf16_length; ++i)
                            {
                                CefKeyEvent key_event;
                                key_event.type = KEYEVENT_CHAR;
                                key_event.character = utf16_data[i]; // Access individual char16 code unit
                                key_event.windows_key_code = 0;      // Not a raw key event
                                key_event.native_key_code = 0;
                                app->inject_key_event(key_event);
                            }
                        }
                    }
                    break;
                }
                else if (event.type == SDL_EVENT_KEY_DOWN)
                {
                    if (!io.WantCaptureKeyboard)
                    {
                        CefKeyEvent key_event;
                        key_event.type = KEYEVENT_KEYDOWN;
                        // Map SDL_Scancode/SDL_Keycode to CEF virtual key codes
                        // This is the trickiest part and requires a mapping function
                        key_event.windows_key_code = event.key.key;     // Not always direct
                        key_event.native_key_code = event.key.scancode; // More reliable for raw key codes
                        key_event.is_system_key = false;                // Usually false for regular keys
                        key_event.character = 0;

                        // Crucial: Set character for control keys
                        switch (event.key.key)
                        {
                        case SDLK_BACKSPACE:
                            key_event.character = '\b';
                            break; // ASCII Backspace
                        case SDLK_RETURN:
                            key_event.character = '\r';
                            break; // ASCII Carriage Return (often '\n' also works)
                        case SDLK_DELETE:
                            key_event.character = 0x7F;
                            break; // ASCII DEL (sometimes 0x00, but 0x7F more common for Delete)
                        case SDLK_TAB:
                            key_event.character = '\t';
                            break; // ASCII Tab
                        default:
                            key_event.character = 0;
                            break; // For other RAWKEYDOWN, no character
                        }

                        // std::cout << "key down debug " << key_event.windows_key_code << std::endl;

                        // Set modifiers (Shift, Ctrl, Alt)
                        if (event.key.mod & SDL_KMOD_SHIFT)
                            key_event.modifiers |= EVENTFLAG_SHIFT_DOWN;
                        if (event.key.mod & SDL_KMOD_CTRL)
                            key_event.modifiers |= EVENTFLAG_CONTROL_DOWN;
                        if (event.key.mod & SDL_KMOD_ALT)
                            key_event.modifiers |= EVENTFLAG_ALT_DOWN;
                        if (event.key.mod & SDL_KMOD_GUI) // KMOD_GUI for Cmd key on Mac
                            key_event.modifiers |= EVENTFLAG_COMMAND_DOWN;

                        std::cout << "SDL_KEYDOWN: SDL_Keycode=" << event.key.key
                                  << " (0x" << std::hex << event.key.key << std::dec << ")"
                                  << ", SDL_Scancode=" << event.key.scancode
                                  << " -> CEF_KeyEvent: windows_key_code=" << key_event.windows_key_code
                                  << " (0x" << std::hex << key_event.windows_key_code << std::dec << ")"
                                  << ", type=RAWKEYDOWN"
                                  << ", modifiers=" << key_event.modifiers << std::endl;
                        app->inject_key_event(key_event);
                    }
                }
                else if (event.type == SDL_EVENT_KEY_UP)
                {
                    if (!io.WantCaptureKeyboard)
                    {
                        CefKeyEvent key_event;
                        key_event.type = KEYEVENT_KEYUP;
                        // Map SDL_Scancode/SDL_Keycode to CEF virtual key codes
                        // This is the trickiest part and requires a mapping function
                        key_event.windows_key_code = event.key.key;     // Not always direct
                                                                        // std::cout << "key up debug " << key_event.windows_key_code << std::endl;
                        key_event.native_key_code = event.key.scancode; // More reliable for raw key codes
                        key_event.is_system_key = false;                // Usually false for regular keys
                        key_event.character = 0;

                        // Crucial: Set character for control keys
                        switch (event.key.key)
                        {
                        case SDLK_BACKSPACE:
                            key_event.character = '\b';
                            break; // ASCII Backspace
                        case SDLK_RETURN:
                            key_event.character = '\r';
                            break; // ASCII Carriage Return (often '\n' also works)
                        case SDLK_DELETE:
                            key_event.character = 0x7F;
                            break; // ASCII DEL (sometimes 0x00, but 0x7F more common for Delete)
                        case SDLK_TAB:
                            key_event.character = '\t';
                            break; // ASCII Tab
                        default:
                            key_event.character = 0;
                            break; // For other RAWKEYDOWN, no character
                        }

                        // Set modifiers (Shift, Ctrl, Alt)
                        if (event.key.mod & SDL_KMOD_SHIFT)
                            key_event.modifiers |= EVENTFLAG_SHIFT_DOWN;
                        if (event.key.mod & SDL_KMOD_CTRL)
                            key_event.modifiers |= EVENTFLAG_CONTROL_DOWN;
                        if (event.key.mod & SDL_KMOD_ALT)
                            key_event.modifiers |= EVENTFLAG_ALT_DOWN;
                        if (event.key.mod & SDL_KMOD_GUI)
                            key_event.modifiers |= EVENTFLAG_COMMAND_DOWN;

                        std::cout << "SDL_KEYUP: SDL_Keycode=" << event.key.key
                                  << " (0x" << std::hex << event.key.key << std::dec << ")"
                                  << ", SDL_Scancode=" << event.key.scancode
                                  << " -> CEF_KeyEvent: windows_key_code=" << key_event.windows_key_code
                                  << " (0x" << std::hex << key_event.windows_key_code << std::dec << ")"
                                  << ", type=KEYUP"
                                  << ", modifiers=" << key_event.modifiers << std::endl;

                        app->inject_key_event(key_event);
                    }
                }
            }
            if (windowSizeDirty || depthTexture == nullptr)
            {
                // glm::mat4 modelView = glm::translate(glm::mat4(1.0), glm::vec3(0.0f, 0.0f, 0.0f));
                // glm::mat4 scaleMatrix = glm::scale(glm::mat4(1.0), glm::vec3(display_scale, display_scale, 0.0f));
                // glm::mat4 modelView = glm::translate(scaleMatrix, glm::vec3(offsetX, offsetY, 0.0f));
                // std::cout << "screen width " << width << " height " << height << std::endl;
                // glm::mat4 projection = glm::ortho(0.0f, (float)width, (float)height, 0.0f, 1.0f, -1.0f);
                glm::mat4 projection = glm::ortho(0.0f, (float)prevWinWidth, (float)prevWinHeight, 0.0f, 1.0f, -1.0f);
                //  simd::float2 offset_vec = {offsetX, offsetY};
                //  memcpy(offset_buffer->contents(), &offset_vec, sizeof(simd::float2));

                simd::float4x4 projection_matrix_buf =
                    {
                        simd::float4{projection[0][0], projection[0][1], projection[0][2], projection[0][3]},
                        simd::float4{projection[1][0], projection[1][1], projection[1][2], projection[1][3]},
                        simd::float4{projection[2][0], projection[2][1], projection[2][2], projection[2][3]},
                        simd::float4{projection[3][0], projection[3][1], projection[3][2], projection[3][3]},
                    };

                memcpy(projection_buffer->contents(), &projection_matrix_buf, sizeof(simd::float4x4));

                layer->setDrawableSize(CGSizeMake(prevWinWidth, prevWinHeight));

                MTL::TextureDescriptor *pDepthTextureDesc = MTL::TextureDescriptor::alloc()->init();
                pDepthTextureDesc->setWidth(prevWinWidth);
                pDepthTextureDesc->setHeight(prevWinHeight);
                pDepthTextureDesc->setPixelFormat(MTL::PixelFormatDepth32Float_Stencil8);
                pDepthTextureDesc->setTextureType(MTL::TextureType2D);
                pDepthTextureDesc->setStorageMode(MTL::StorageModePrivate);
                pDepthTextureDesc->setUsage(MTL::ResourceUsageSample | MTL::ResourceUsageRead | MTL::ResourceUsageWrite);
                if (depthTexture)
                {
                    depthTexture->release();
                }
                depthTexture = layer->device()->newTexture(pDepthTextureDesc);
                pDepthTextureDesc->release();
                // renderOutputWidth = width;
                // renderOutputHeight = height;
            }
            auto drawable = layer->nextDrawable();

            MTL::CommandBuffer *commandBuffer = commandQueue->commandBuffer();
            renderPassDescriptor->colorAttachments()->object(0)->setClearColor(MTL::ClearColor::Make(clear_color[0] * clear_color[3], clear_color[1] * clear_color[3], clear_color[2] * clear_color[3], clear_color[3]));
            renderPassDescriptor->colorAttachments()->object(0)->setTexture(drawable->texture());
            renderPassDescriptor->colorAttachments()->object(0)->setLoadAction(MTL::LoadAction::LoadActionClear);
            renderPassDescriptor->colorAttachments()->object(0)->setStoreAction(MTL::StoreAction::StoreActionStore);
            renderPassDescriptor->depthAttachment()->setTexture(depthTexture);
            renderPassDescriptor->depthAttachment()->setClearDepth(1.0);
            renderPassDescriptor->depthAttachment()->setStoreAction(MTL::StoreAction::StoreActionDontCare);
            renderPassDescriptor->stencilAttachment()->setTexture(depthTexture);
            renderPassDescriptor->stencilAttachment()->setLoadAction(MTL::LoadActionClear);
            renderPassDescriptor->stencilAttachment()->setClearStencil(0);
            renderPassDescriptor->stencilAttachment()->setStoreAction(MTL::StoreActionStore);
            MTL::RenderCommandEncoder *renderEncoder = commandBuffer->renderCommandEncoder(renderPassDescriptor);
            renderEncoder->pushDebugGroup(NS::String::string("triangle demo", NS::UTF8StringEncoding));

            app->encode_render_command(renderEncoder, projection_buffer);

            renderEncoder->popDebugGroup();
            CefDoMessageLoopWork();
            app->request_new_frame();

            renderEncoder->pushDebugGroup(NS::String::string("ImGui demo", NS::UTF8StringEncoding));
            // Start the Dear ImGui frame
            ImGui_ImplMetal_NewFrame((__bridge MTLRenderPassDescriptor *)renderPassDescriptor);
            ImGui_ImplSDL3_NewFrame();
            ImGui::NewFrame();

            // 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
            if (show_demo_window)
                ImGui::ShowDemoWindow(&show_demo_window);
            // ImGui::SetMouseCursor(ImGuiMouseCursor_TextInput);
            //  2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
            {

                static int counter = 0;

                ImGui::Begin("Hello, world!"); // Create a window called "Hello, world!" and append into it.
                ImGui::Checkbox("Show Text Objects", &show_text_objects);
                ImGui::Checkbox("Show Char Objects", &show_char_objects);
                ImGui::Text("Joints."); // Display some text (you can use a format strings too)

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
            ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), (__bridge id<MTLCommandBuffer>)commandBuffer, (__bridge id<MTLRenderCommandEncoder>)renderEncoder);

            renderEncoder->popDebugGroup();
            renderEncoder->endEncoding();

            commandBuffer->presentDrawable(drawable);
            commandBuffer->commit();
        }
    }

    app->close(true);

    while (!app->is_browser_closed())
    {
        CefDoMessageLoopWork(); // Or sleep a bit i
    }
    CefQuitMessageLoop();

    depthTexture->release();
    renderPassDescriptor->release();
    commandQueue->release();
    projection_buffer->release();

    // Cleanup
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplSDL3_Shutdown();
    ImGui::DestroyContext();

    SDL_DestroyWindow(window);
    SDL_Quit();
    CefShutdown();
    return 0;
}
