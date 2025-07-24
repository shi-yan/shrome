#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/cef_command_line.h" // Required for CefCommandLine

#include <iostream>
#include <vector>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

// Implement CefRenderHandler for offscreen rendering
class MyRenderHandler : public CefRenderHandler
{
public:
    MyRenderHandler() = default;

    // CefRenderHandler methods
    void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) override
    {
        // Define the size of your offscreen render area.
        // This tells CEF the dimensions at which to render the web content.
        rect = CefRect(0, 0, 1280, 720); // Example: 1280x720 pixels [1]
    }

    void OnPaint(CefRefPtr<CefBrowser> browser,
                 PaintElementType type,
                 const RectList &dirtyRects,
                 const void *buffer,
                 int width,
                 int height) override
    {
        // This is where you receive the raw pixel data.
        // 'buffer' contains the pixel data (RGBA, 32-bit per pixel).
        // 'width' and 'height' are the dimensions of the buffer.
        // 'dirtyRects' specifies the regions that have changed and need updating. [2]
        std::cout << "Received OnPaint data: " << width << "x" << height << " pixels. Dirty regions: " << dirtyRects.size() << std::endl;

        int result = stbi_write_jpg("debug.jpg", width, height, 4, buffer, 100);

        if (result == 0)
        {
            printf("Error writing image\n");
            return;
        }
        else
        {
            printf("Image written successfully\n");
        }
        // In a real application, you would copy this 'buffer' data to your
        // rendering target (e.g., an OpenGL texture, a Metal texture, or a bitmap)
        // and then display it.
        // For simplicity, we're just printing a message here.
        // Example: memcpy(my_texture_buffer, buffer, width * height * 4); [1]
    }

    // Other CefRenderHandler methods can be left as default or implemented as needed.

private:
    IMPLEMENT_REFCOUNTING(MyRenderHandler);
};

// Implement CefClient to provide the RenderHandler
class MyClient : public CefClient
{
public:
    MyClient(CefRefPtr<MyRenderHandler> render_handler) : render_handler_(render_handler) {}

    CefRefPtr<CefRenderHandler> GetRenderHandler() override
    {
        return render_handler_; // [1]
    }

private:
    CefRefPtr<MyRenderHandler> render_handler_;
    IMPLEMENT_REFCOUNTING(MyClient);
};

// Implement CefApp and CefBrowserProcessHandler
class MyApp : public CefApp,
              public CefBrowserProcessHandler
{
public:
    MyApp() = default;

    // CefApp methods
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override
    {
        return this;
    }

    // CefBrowserProcessHandler methods
    void OnContextInitialized() override
    {
        CefBrowserSettings browser_settings;
        browser_settings.windowless_frame_rate = 30;
        // Transparent painting is enabled by default in OSR, but can be disabled
        // by setting background_color to an opaque value. [3]
        // browser_settings.background_color = 0xFFFFFFFF; // Opaque white background

        CefWindowInfo window_info;
        // Crucial for OSR: Use SetAsWindowless instead of SetAsOffScreen.
        // The 'parent' handle can be nullptr if not strictly necessary for dialog parenting or monitor info. [3, 4]
        window_info.SetAsWindowless(nullptr); // [5, 1]
        window_info.external_begin_frame_enabled = true;

        CefRefPtr<MyRenderHandler> render_handler = new MyRenderHandler();
        CefRefPtr<MyClient> client = new MyClient(render_handler);

        // Create the offscreen browser
        // You might want to load a specific URL here instead of "about:blank"
        CefBrowserHost::CreateBrowser(window_info, client, "https://www.youtube.com/watch?v=9v_lNeyg1xE", browser_settings, nullptr, nullptr); // [1]
    }

private:
    IMPLEMENT_REFCOUNTING(MyApp);
};

int main(int argc, char **argv)
{
    // Load the CEF library. This is required for macOS.
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInMain())
    {
        return 1;
    }

    CefMainArgs main_args(argc, argv);
    CefRefPtr<MyApp> app(new MyApp);

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

    // This will block until CefQuitMessageLoop() is called.
    // In a real application, you might integrate this into your own event loop
    // using CefDoMessageLoopWork() if you have a custom UI framework. [1]
    CefRunMessageLoop();

    CefShutdown(); // [1]
    return 0;
}
