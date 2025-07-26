#ifndef MYCEF_H
#define MYCEF_H
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <simd/simd.h>
#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/cef_command_line.h" // Required for CefCommandLine

#include <iostream>
#include <vector>
#include <functional>
#include "imgui.h"
// #define STB_IMAGE_WRITE_IMPLEMENTATION
// #include "stb_image_write.h"

//--off-screen-rendering-enabled

using RenderingCallback = std::function<void(CefRenderHandler::PaintElementType type,
                                             const CefRenderHandler::RectList &dirtyRects,
                                             const void *buffer,
                                             int width,
                                             int height)>;

using PopupShowCallback = std::function<void(bool show)>;

using PopupSizedCallback = std::function<void(const CefRect &rect)>;

// Implement CefRenderHandler for offscreen rendering
class MyRenderHandler : public CefRenderHandler
{
public:
    int m_width = 0;
    int m_height = 0;
    int m_pixel_density = 1;
    MyRenderHandler(int width, int height, int pixel_density, RenderingCallback rendering_callback, PopupShowCallback popup_show_callback,
                    PopupSizedCallback popup_sized_callback);

    RenderingCallback m_rendering_callback;
    PopupShowCallback m_popup_show_callback;
    PopupSizedCallback m_popup_sized_callback;

    // CefRenderHandler methods
    void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) override
    {
        // Define the size of your offscreen render area.
        // This tells CEF the dimensions at which to render the web content.
        rect = CefRect(0, 0, m_width, m_height); // Example: 1280x720 pixels [1]
    }

    bool GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& screen_info) override {
 
        float dpi_scale_factor = m_pixel_density;

        screen_info.device_scale_factor = dpi_scale_factor;

        screen_info.rect = CefRect(0, 0, m_width, m_height); // Full screen in DIPs
        screen_info.available_rect = CefRect(0, 0, m_width, m_height); // Usable screen in DIPs (e.g., excluding taskbars)

        return true; // Indicate that you provided the information
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
        /*std::cout << "Received OnPaint data: " << width << "x" << height << " pixels. Dirty regions: " << dirtyRects.size() << std::endl;

        int result = stbi_write_jpg("debug.jpg", width, height, 4, buffer, 100);

        if (result == 0)
        {
            printf("Error writing image\n");
            return;
        }
        else
        {
            printf("Image written successfully\n");
        }*/
        // In a real application, you would copy this 'buffer' data to your
        // rendering target (e.g., an OpenGL texture, a Metal texture, or a bitmap)
        // and then display it.
        // For simplicity, we're just printing a message here.
        // Example: memcpy(my_texture_buffer, buffer, width * height * 4); [1]

        if (m_rendering_callback)
        {
            m_rendering_callback(type, dirtyRects, buffer, width, height);
        }
    }

    // Other CefRenderHandler methods can be left as default or implemented as needed.

    void OnPopupShow(CefRefPtr<CefBrowser> browser, bool show) override
    {
        m_popup_show_callback(show);
    }

    ///
    /// Called when the browser wants to move or resize the popup widget. |rect|
    /// contains the new location and size in view coordinates.
    ///
    /*--cef()--*/
    void OnPopupSize(CefRefPtr<CefBrowser> browser, const CefRect &rect) override
    {
        m_popup_sized_callback(rect);
    }

private:
    IMPLEMENT_REFCOUNTING(MyRenderHandler);
};

// Implement CefClient to provide the RenderHandler
class MyClient : public CefClient,
                 public CefLifeSpanHandler,
                 public CefDisplayHandler,
                 public CefContextMenuHandler,
                 public CefKeyboardHandler // <--- Add this
{
public:
    ImGuiMouseCursor m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
    bool m_closed = false;

    // ... existing members ...
    CefRefPtr<CefBrowser> m_browser; // Your browser instance

    MyClient(CefRefPtr<MyRenderHandler> render_handler) : render_handler_(render_handler) {}

    CefRefPtr<CefRenderHandler> GetRenderHandler() override
    {
        return render_handler_; // [1]
    }

    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }

    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override
    {
        return this;
    }
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; } // Return 'this' or a dedicated handler instance
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override
    {
        return this; // Return a reference to yourself
    }

    bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                       const CefKeyEvent &event,
                       CefEventHandle os_event,
                       bool *is_keyboard_shortcut) override
    {
        // This is called BEFORE the browser processes the key event.
        // Return true to block default processing.
        std::cout << "OnPreKeyEvent: Type=" << event.type
                  << ", VK=" << event.windows_key_code
                  << ", NK=" << event.native_key_code
                  << ", Char=" << event.character
                  << ", Modifiers=" << event.modifiers 
                  << ", unmodified_char " << event.unmodified_character
                  << ", is_system_key " << event.is_system_key
                  << ", focus_on_editable_field " << event.focus_on_editable_field
                  << std::endl;
        return false; // Don't block for now
    }

    bool OnKeyEvent(CefRefPtr<CefBrowser> browser,
                    const CefKeyEvent &event,
                    CefEventHandle os_event) override
    {
        // This is called AFTER the browser processes the key event.
        // Return true if you handled it and CEF should not do default processing.
         std::cout << "OnKeyEvent: Type=" << event.type
                  << ", VK=" << event.windows_key_code
                  << ", NK=" << event.native_key_code
                  << ", Char=" << event.character
                  << ", Modifiers=" << event.modifiers 
                  << ", unmodified_char " << event.unmodified_character
                  << ", is_system_key " << event.is_system_key
                  << ", focus_on_editable_field " << event.focus_on_editable_field
                  << std::endl;
        return false; // Don't block for now
    }

    // CefContextMenuHandler methods:
    // Implement at least these two to prevent common crashes
    void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             CefRefPtr<CefContextMenuParams> params,
                             CefRefPtr<CefMenuModel> model) override
    {
        // This method is called before the context menu is displayed.
        // You can modify 'model' to add/remove/change menu items here.
        // For now, let's just clear it to prevent any default menu from showing.
        // If you want to show a default menu, do not clear it.
        model->Clear();
    }

    bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefContextMenuParams> params,
                              int command_id,
                              EventFlags event_flags) override
    {
        // This method is called when a context menu item is clicked.
        // Return true if you handled the command, false otherwise.
        // Since we cleared the model, this might not be called, but it's good practice.
        return false;
    }

    // CefLifeSpanHandler methods
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override; // This is the key method
    bool DoClose(CefRefPtr<CefBrowser> browser) override
    {
        // Return false to allow the close to proceed
        return false;
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override
    {
        m_closed = true;
        m_browser = nullptr;
        std::cout << "browser closed ====== " << std::endl;
    }


    void request_new_frame()
    {
        if (m_browser && m_browser->IsValid())
        {
            if (m_browser->GetHost()->IsWindowRenderingDisabled())
            {
                m_browser->GetHost()->SendExternalBeginFrame();
            }
        }
    }

    void inject_key_event(const CefKeyEvent &event)
    {
        if (m_browser && m_browser->IsValid())
        {
            std::cout << "inject key event: " << event.type << std::endl;
            m_browser->GetHost()->SendKeyEvent(event);
        }
    }

    void inject_mouse_motion(const CefMouseEvent &mouse_event)
    {
        if (m_browser && m_browser->IsValid())
        {
            m_browser->GetHost()->SendMouseMoveEvent(mouse_event, false); // false for mouse not leaving
        }
    }

    void inject_mouse_up_down(const CefMouseEvent &event,
                              CefBrowserHost::MouseButtonType type,
                              bool mouseUp,
                              int clickCount)
    {
        if (m_browser && m_browser->IsValid())
        {
            if (!mouseUp)
            {
                m_browser->GetHost()->SetFocus(true);
            }
            // std::cout << "injected mouse up down " << mouseUp << std::endl;
            m_browser->GetHost()->SendMouseClickEvent(event, type, mouseUp, clickCount);
        }
    }

    void close_browser(bool force_close = true)
    {
        if (m_browser && m_browser->IsValid())
        {
            std::cout << "browser closed" << std::endl;
            m_browser->GetHost()->CloseBrowser(force_close);
        }
    }

    void inject_mouse_wheel(const CefMouseEvent &event,
                            int deltaX,
                            int deltaY)
    {
        if (m_browser && m_browser->IsValid())
        {
            m_browser->GetHost()->SendMouseWheelEvent(event, deltaX, deltaY);
        }
    }

    bool OnCursorChange(CefRefPtr<CefBrowser> browser,
                        CefCursorHandle cursor,
                        cef_cursor_type_t type,
                        const CefCursorInfo &custom_cursor_info) override
    {

        switch (type)
        {
        case CT_POINTER:
        case CT_CONTEXTMENU: // Often the same as pointer
            m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
            break;

        case CT_HAND: // Pointing hand for links
            m_imgui_cursor_type = ImGuiMouseCursor_Hand;
            break;

        case CT_CROSS: // Crosshair
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeAll;
            break;

        case CT_IBEAM:        // Text selection
        case CT_VERTICALTEXT: // Vertical text is still an IBeam
            m_imgui_cursor_type = ImGuiMouseCursor_TextInput;
            break;

        case CT_WAIT:                                         // Loading/busy indicator
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeAll; // ImGui doesn't have a direct "wait" spinner. ResizeAll or Arrow are common fallbacks.
            // A better approach for "wait" might be to render a custom spinner in ImGui or use a custom ImGui cursor.
            break;

        case CT_HELP:
            // ImGui doesn't have a direct "help" cursor. Arrow is a common fallback.
            m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
            break;

        // Resize cursors: ImGui has specific ones for horizontal, vertical, and diagonal.
        // CEF's types are more granular, so we map to the closest ImGui equivalent.
        case CT_NORTHSOUTHRESIZE:
        case CT_ROWRESIZE:
        case CT_NORTHRESIZE:
        case CT_SOUTHRESIZE:
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeNS;
            break;

        case CT_EASTWESTRESIZE:
        case CT_COLUMNRESIZE:
        case CT_EASTRESIZE:
        case CT_WESTRESIZE:
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeEW;
            break;

        case CT_NORTHEASTSOUTHWESTRESIZE: // Diagonal \ (top-right to bottom-left)
        case CT_NORTHEASTRESIZE:
        case CT_SOUTHWESTRESIZE:
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeNESW;
            break;

        case CT_NORTHWESTSOUTHEASTRESIZE: // Diagonal / (top-left to bottom-right)
        case CT_NORTHWESTRESIZE:
        case CT_SOUTHEASTRESIZE:
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeNWSE;
            break;

        case CT_MOVE:
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeAll; // Closest ImGui has for general move/size
            break;

        case CT_NOTALLOWED:
        case CT_NODROP:
        case CT_DND_NONE: // Drag and drop "not allowed"
            m_imgui_cursor_type = ImGuiMouseCursor_NotAllowed;
            break;

        case CT_CELL:
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeAll; // Crosshair is a common choice for cell
            break;

        case CT_GRAB:     // Open hand (for grabbing/dragging)
        case CT_GRABBING: // Closed hand (while grabbing)
            // ImGui doesn't have distinct open/closed hand system cursors.
            // ImGuiMouseCursor_Hand is the closest for general "grab" behavior.
            m_imgui_cursor_type = ImGuiMouseCursor_Hand;
            break;

        case CT_DND_COPY:
        case CT_COPY:
            // ImGui doesn't have a system "copy" cursor directly. Arrow is a reasonable fallback.
            m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
            break;

        case CT_DND_LINK:
        case CT_ALIAS:
            // ImGui doesn't have a system "link" cursor directly. Arrow is a reasonable fallback.
            m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
            break;

        case CT_DND_MOVE:
            // ImGui doesn't have a distinct "drag move" cursor. ResizeAll or Arrow.
            m_imgui_cursor_type = ImGuiMouseCursor_ResizeAll;
            break;

        case CT_ZOOMIN:
        case CT_ZOOMOUT:
            // No direct ImGui system cursor. Arrow or Crosshair.
            m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
            break;

        case CT_CUSTOM:
        {
            // This is still the most complex case. ImGui's SetMouseCursor
            // only takes its predefined enum values.
            // To use a custom cursor from CEF:
            // 1. You would need to get the pixel data from the `cursor` handle/`custom_cursor_info`.
            // 2. Create an ImGui texture from this data.
            // 3. Render this custom texture yourself at the mouse position within your ImGui frame.
            // This means you wouldn't use ImGui::SetMouseCursor for custom cursors,
            // but rather draw your own ImGui window/overlay for the cursor.
            m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
            break;
        }

        default:
            m_imgui_cursor_type = ImGuiMouseCursor_Arrow; // Fallback for any unhandled or unknown types
            break;
        }
        // Return true to indicate that you handled the cursor change.
        // Returning false would tell CEF to use its default cursor, which is not what you want for OSR.
        return true;
    }

private:
    CefRefPtr<MyRenderHandler> render_handler_;
    IMPLEMENT_REFCOUNTING(MyClient);
};

// Implement CefApp and CefBrowserProcessHandler
class MyApp final : public CefApp,
                    public CefBrowserProcessHandler
{
public:
    MTL::Device *m_metal_device = nullptr;
    MTL::Texture *m_texture = nullptr;
    bool m_should_show_popup = false;
    CefRect m_popup_pos;
    MTL::Buffer *m_popup_offset_buffer = nullptr;
    MTL::Buffer *m_zero_offset_buffer = nullptr;
    MTL::Texture *m_popup_texture = nullptr;

    uint32_t m_texture_width = 0;
    uint32_t m_texture_height = 0;
    uint32_t m_popup_texture_width = 0;
    uint32_t m_popup_texture_height = 0;

    uint32_t m_window_width = 1280;
    uint32_t m_window_height = 720;
    uint32_t m_pixel_density = 1;
    CefRefPtr<MyClient> m_client;

    MTL::DepthStencilState *m_depth_stencil_state_disabled = nullptr;
    MTL::Buffer *m_triangle_vertex_buffer = nullptr;
    MTL::Buffer *m_popup_triangle_vertex_buffer = nullptr;

    MTL::RenderPipelineState *m_render_pipeline = nullptr;

    RenderingCallback m_on_texture_ready;
    PopupShowCallback m_popup_show_callback;
    PopupSizedCallback m_popup_sized_callback;

    MyApp(MTL::Device *metal_device, uint32_t window_width, uint32_t window_height, uint32_t pixel_density);

    void init(MTL::Device *metal_device, MTL::PixelFormat pixel_format, uint32_t window_width, uint32_t window_height);

    ~MyApp();

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

        CefRefPtr<MyRenderHandler> render_handler = new MyRenderHandler(m_window_width, m_window_height, m_pixel_density, m_on_texture_ready, m_popup_show_callback, m_popup_sized_callback);
        m_client = new MyClient(render_handler);

        // Create the offscreen browser
        // You might want to load a specific URL here instead of "about:blank"
        CefBrowserHost::CreateBrowser(window_info, m_client, "https://google.com", browser_settings, nullptr, nullptr); // [1]
    }

    void close(bool force_close)
    {
        if (m_client)
        {
            m_client->close_browser(force_close);
        }
    }

    bool is_browser_closed()
    {
        if (m_client)
        {
            return m_client->m_closed;
        }
        return true;
    }

    void request_new_frame()
    {
        if (m_client)
        {
            m_client->request_new_frame();
        }
    }

    void inject_mouse_motion(const CefMouseEvent &motion)
    {
        if (m_client)
        {
            m_client->inject_mouse_motion(motion);
        }
    }

    ImGuiMouseCursor get_cursor_type()
    {
        if (m_client)
        {
            return m_client->m_imgui_cursor_type;
        }
        return ImGuiMouseCursor_Arrow;
    }

    void inject_mouse_up_down(const CefMouseEvent &event,
                              CefBrowserHost::MouseButtonType type,
                              bool mouseUp,
                              int clickCount)
    {
        if (m_client)
        {
            // std::cout << "injected mouse up down 1" << mouseUp << std::endl;
            m_client->inject_mouse_up_down(event, type, mouseUp, clickCount);
        }
    }

    void inject_mouse_wheel(const CefMouseEvent &event,
                            int deltaX,
                            int deltaY)
    {
        if (m_client)
        {
            m_client->inject_mouse_wheel(event, deltaX, deltaY);
        }
    }

    void inject_key_event(const CefKeyEvent &event)
    {
        if (m_client)
        {
            m_client->inject_key_event(event);
        }
    }

    void OnBeforeCommandLineProcessing(const CefString &process_type,
                                       CefRefPtr<CefCommandLine> command_line) override;

    void encode_render_command(MTL::RenderCommandEncoder *render_command_encoder,
                               MTL::Buffer *projection_buffer);

private:
    IMPLEMENT_REFCOUNTING(MyApp);
};

#endif // MYCEF_H
