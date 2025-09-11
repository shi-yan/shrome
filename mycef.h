#ifndef MYCEF_H
#define MYCEF_H

#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/cef_focus_handler.h"
#include "include/cef_command_line.h" // Required for CefCommandLine
#include <IOSurface/IOSurface.h>
#include <iostream>
#include <vector>
#include <functional>
#include "imgui.h"

//--off-screen-rendering-enabled

namespace MTL
{
    class Device;
    class Texture;
    class Buffer;
    class DepthStencilState;
    class RenderPipelineState;
    class RenderCommandEncoder;
};

std::string get_macos_cache_dir(const std::string &app_name);

using RenderingCallback = std::function<void(CefRenderHandler::PaintElementType type,
                                             const CefRenderHandler::RectList &dirtyRects,
                                             const void *buffer,
                                             int width,
                                             int height)>;

using AcceleratedRenderingCallback = std::function<void(CefRenderHandler::PaintElementType type,
                                                        const CefRenderHandler::RectList &dirtyRects,
                                                        IOSurfaceRef io_surface)>;

using PopupShowCallback = std::function<void(bool show)>;

using PopupSizedCallback = std::function<void(const CefRect &rect)>;

// Implement CefRenderHandler for offscreen rendering
class MyRenderHandler : public CefRenderHandler
{
public:
    bool m_accelerated_rendering = false;
    int m_width = 0;
    int m_height = 0;
    int m_pixel_density = 1;
    std::string m_selected_text; // Track selected text

    MyRenderHandler(bool accelerated_rendering, int width, int height, int pixel_density,
                    RenderingCallback rendering_callback,
                    AcceleratedRenderingCallback accelerated_rendering_callback,
                    PopupShowCallback popup_show_callback,
                    PopupSizedCallback popup_sized_callback);

    // Method to update dimensions and pixel density
    void UpdateDimensions(int width, int height, int pixel_density);

    RenderingCallback m_rendering_callback;
    AcceleratedRenderingCallback m_accelerated_rendering_callback;
    PopupShowCallback m_popup_show_callback;
    PopupSizedCallback m_popup_sized_callback;

    // CefRenderHandler methods
    void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) override
    {
        // Get the current view dimensions dynamically
        // This ensures CEF renders at the correct size even after resize
        rect = CefRect(0, 0, m_width, m_height);
    }

    bool GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo &screen_info) override
    {

        float dpi_scale_factor = m_pixel_density;

        screen_info.device_scale_factor = dpi_scale_factor;

        screen_info.rect = CefRect(0, 0, m_width, m_height);           // Full screen in DIPs
        screen_info.available_rect = CefRect(0, 0, m_width, m_height); // Usable screen in DIPs (e.g., excluding taskbars)
                                                                       // std::cout << "get screen info: " << m_width << ", " << m_height << ", " << dpi_scale_factor << std::endl;
        return true;                                                   // Indicate that you provided the information
    }

    void OnAcceleratedPaint(CefRefPtr<CefBrowser> browser,
                            CefRenderHandler::PaintElementType type,
                            const CefRenderHandler::RectList &dirtyRects,
                            const CefAcceleratedPaintInfo &info) override
    {
        // Handle accelerated paint events here if needed
        // For now, we can ignore this if not using accelerated painting

        IOSurfaceRef io_surface = (IOSurfaceRef)info.shared_texture_io_surface;

        if (m_accelerated_rendering && m_accelerated_rendering_callback)
        {
            m_accelerated_rendering_callback(type, dirtyRects, io_surface);
        }
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

        if (!m_accelerated_rendering && m_rendering_callback)
        {
            m_rendering_callback(type, dirtyRects, buffer, width, height);
        }
        // std::cout << "on paint called: " << width << ", " << height << std::endl;
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

    // Track text selection changes
    void OnTextSelectionChanged(CefRefPtr<CefBrowser> browser,
                               const CefString& selected_text,
                               const CefRange& selected_range) override
    {
        m_selected_text = selected_text.ToString();
        std::cout << "Text selection changed: '" << m_selected_text << "'" << std::endl;
    }

private:
    IMPLEMENT_REFCOUNTING(MyRenderHandler);
};

// Implement CefClient to provide the RenderHandler
class MyClient : public CefClient,
                 public CefLifeSpanHandler,
                 public CefDisplayHandler,
                 public CefContextMenuHandler,
                 public CefKeyboardHandler,
                 public CefFocusHandler,
                 public CefCommandHandler
{
public:
    ImGuiMouseCursor m_imgui_cursor_type = ImGuiMouseCursor_Arrow;
    bool m_closed = false;
    bool m_has_focus = false;
    CefRefPtr<MyRenderHandler> m_render_handler;

    // Context menu state
    bool m_show_context_menu = false;
    std::vector<std::pair<int, std::string>> m_context_menu_items;
    float m_context_menu_x = 0.0f;
    float m_context_menu_y = 0.0f;

    // ... existing members ...
    CefRefPtr<CefBrowser> m_browser; // Your browser instance

    MyClient(CefRefPtr<MyRenderHandler> render_handler) : m_render_handler(render_handler) {}

    CefRefPtr<CefRenderHandler> GetRenderHandler() override
    {
        return m_render_handler; // [1]
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

    CefRefPtr<CefFocusHandler> GetFocusHandler() override
    {
        return this; // Return a reference to yourself
    }

    void OnGotFocus(CefRefPtr<CefBrowser> browser) override
    {
        m_has_focus = true;
    }

    void OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next) override
    {
        m_has_focus = false;
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

        // Handle keyboard shortcuts
        if (event.type == KEYEVENT_KEYDOWN || event.type == KEYEVENT_RAWKEYDOWN) {
            bool is_cmd = (event.modifiers & EVENTFLAG_COMMAND_DOWN) != 0;
            
            if (is_cmd) {
                std::cout << "Cmd key detected with character: '" << (char)event.unmodified_character << "' (code: " << (int)event.unmodified_character << ")" << std::endl;
                switch (event.unmodified_character) {
                    case 'z':
                    case 'Z':
                        if (event.modifiers & EVENTFLAG_SHIFT_DOWN) {
                            redo();
                        } else {
                            undo();
                        }
                        *is_keyboard_shortcut = true;
                        return true; // Block CEF processing
                        
                    case 'x':
                    case 'X':
                        std::cout << "Cut shortcut detected" << std::endl;
                        // Let CEF handle cut, then add our clipboard workaround
                        *is_keyboard_shortcut = true;
                        cut();
                        return true;
                        
                    case 'c':
                    case 'C':
                        std::cout << "Copy shortcut detected" << std::endl;
                        // Let CEF handle copy, then add our clipboard workaround
                        *is_keyboard_shortcut = true;
                        copy();
                        return true;
                        
                    case 'v':
                    case 'V':
                        paste();
                        *is_keyboard_shortcut = true;
                        return true;
                        
                    case 'a':
                    case 'A':
                        select_all();
                        *is_keyboard_shortcut = true;
                        return true;
                }
            }
            
            // Handle Delete key (Mac keycode)
            if (event.native_key_code == 0x75) { // Delete key on Mac
                delete_selection();
                return true;
            }
        }
        
        *is_keyboard_shortcut = false;
        return false; // Let CEF handle other keys
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
        // I have to return true here, cef will send an NSEvent when this is false, that event triggers menu shortcuts.
        return true;
    }

    // CefContextMenuHandler methods:
    void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                             CefRefPtr<CefContextMenuParams> params,
                             CefRefPtr<CefMenuModel> model) override
    {
        // Clear default menu and build our own
        model->Clear();
        
        // Store menu position (convert from browser coordinates to screen coordinates if needed)
        m_context_menu_x = params->GetXCoord();
        m_context_menu_y = params->GetYCoord();
        
        // Build menu items based on context
        m_context_menu_items.clear();
        
        // Always available actions
        m_context_menu_items.push_back({1001, "Undo"});
        m_context_menu_items.push_back({1002, "Redo"});
        m_context_menu_items.push_back({-1, ""}); // Separator
        
        // Selection-based actions
        bool has_selection = !params->GetSelectionText().empty();
        if (has_selection) {
            m_context_menu_items.push_back({1003, "Cut"});
            m_context_menu_items.push_back({1004, "Copy"});
        }
        
        // Check if we can paste (this is tricky to determine, so we'll always show it)
        m_context_menu_items.push_back({1005, "Paste"});
        
        if (has_selection) {
            m_context_menu_items.push_back({1006, "Delete"});
        }
        
        m_context_menu_items.push_back({-1, ""}); // Separator
        m_context_menu_items.push_back({1007, "Select All"});
        
        // Don't show the CEF context menu, we'll render with ImGui
        m_show_context_menu = true;
    }

    bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                              CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefContextMenuParams> params,
                              int command_id,
                              EventFlags event_flags) override
    {
        // Handle context menu commands
        switch (command_id) {
            case 1001: // Undo
                undo();
                return true;
            case 1002: // Redo
                redo();
                return true;
            case 1003: // Cut
                std::cout << "Context menu cut selected" << std::endl;
                cut();
                return true;
            case 1004: // Copy
                copy();
                return true;
            case 1005: // Paste
                paste();
                return true;
            case 1006: // Delete
                delete_selection();
                return true;
            case 1007: // Select All
                select_all();
                return true;
        }
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
        //std::cout << "browser closed ====== " << std::endl;
    }

    void request_new_frame()
    {
        if (m_browser && m_browser->IsValid())
        {
            if (m_browser->GetHost()->IsWindowRenderingDisabled())
            {
                // std::cout << "render frame" << std::endl;
                m_browser->GetHost()->SendExternalBeginFrame();
            }
        }
    }

    void inject_key_event(const CefKeyEvent &event)
    {
        if (m_browser && m_browser->IsValid())
        {
            //std::cout << "inject key event: " << event.type << std::endl;
            m_browser->GetHost()->SendKeyEvent(event);
        }
    }

    void copy() {
        if (m_browser && m_browser->IsValid() && m_browser->GetFocusedFrame()) {
            std::cout << "Executing copy operation..." << std::endl;
            m_browser->GetFocusedFrame()->Copy();
            std::cout << "Copy operation completed" << std::endl;
        }
    }

public:

    void cut() {
        if (m_browser && m_browser->IsValid() && m_browser->GetFocusedFrame()) {
            std::cout << "Executing cut operation..." << std::endl;
            m_browser->GetFocusedFrame()->Cut();
            std::cout << "Cut operation completed" << std::endl;
        }
    }

    void paste() {
        if (m_browser && m_browser->IsValid() && m_browser->GetFocusedFrame()) {
            m_browser->GetFocusedFrame()->Paste();
        }
    }

    void undo() {
        if (m_browser && m_browser->IsValid() && m_browser->GetFocusedFrame()) {
            m_browser->GetFocusedFrame()->Undo();
        }
    }

    void redo() {
        if (m_browser && m_browser->IsValid() && m_browser->GetFocusedFrame()) {
            m_browser->GetFocusedFrame()->Redo();
        }
    }

    void delete_selection() {
        if (m_browser && m_browser->IsValid() && m_browser->GetFocusedFrame()) {
            m_browser->GetFocusedFrame()->Delete();
        }
    }

    void select_all() {
        if (m_browser && m_browser->IsValid() && m_browser->GetFocusedFrame()) {
            m_browser->GetFocusedFrame()->SelectAll();
        }
    }

    CefRefPtr<CefBrowser> get_browser()
    {
        return m_browser;
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
            //std::cout << "browser closed" << std::endl;
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

      bool OnChromeCommand(CefRefPtr<CefBrowser> browser,
                       int command_id,
                       cef_window_open_disposition_t disposition) override;

private:
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
    MTL::Buffer *m_triangle_vertex_buffer = nullptr;
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
    // MTL::Buffer *m_triangle_vertex_buffer = nullptr;
    MTL::Buffer *m_popup_triangle_vertex_buffer = nullptr;

    MTL::RenderPipelineState *m_render_pipeline = nullptr;

    RenderingCallback m_on_texture_ready;
    AcceleratedRenderingCallback m_on_accelerated_texture_ready;
    PopupShowCallback m_popup_show_callback;
    PopupSizedCallback m_popup_sized_callback;

    MyApp(MTL::Device *metal_device, uint32_t window_width, uint32_t window_height, uint32_t pixel_density);

    void init(MTL::Device *metal_device, uint64_t pixel_format, uint32_t window_width, uint32_t window_height);

    ~MyApp();

    // CefApp methods
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override
    {
        return this;
    }

    // CefBrowserProcessHandler methods
    void OnContextInitialized() override
    {
        // std::cout << "CefApp::OnContextInitialized called" << std::endl;
        CefBrowserSettings browser_settings;
        browser_settings.windowless_frame_rate = 60;
        // Transparent painting is enabled by default in OSR, but can be disabled
        // by setting background_color to an opaque value. [3]
        // browser_settings.background_color = 0xFFFFFFFF; // Opaque white background

        CefWindowInfo window_info;
        // Crucial for OSR: Use SetAsWindowless instead of SetAsOffScreen.
        // The 'parent' handle can be nullptr if not strictly necessary for dialog parenting or monitor info. [3, 4]
        window_info.SetAsWindowless(nullptr); // [5, 1]
        window_info.external_begin_frame_enabled = true;
        window_info.shared_texture_enabled = true; // Enable shared textures for Metal
        window_info.runtime_style = CEF_RUNTIME_STYLE_CHROME;
        CefRefPtr<MyRenderHandler> render_handler = new MyRenderHandler( window_info.shared_texture_enabled,
            m_window_width, 
            m_window_height, 
            m_pixel_density, 
            m_on_texture_ready, 
            m_on_accelerated_texture_ready,
            m_popup_show_callback, m_popup_sized_callback);
        m_client = new MyClient(render_handler);

        // Create the offscreen browser
        // You might want to load a specific URL here instead of "about:blank"
        CefBrowserHost::CreateBrowser(window_info, m_client, "https://www.youtube.com/watch?v=aDdgU2gPtQQ", browser_settings, nullptr, nullptr); // [1]
    }

    void close(bool force_close)
    {
        if (m_client)
        {
            m_client->close_browser(force_close);
        }
    }

    bool has_focus()
    {
        if (m_client)
        {
            return m_client->m_has_focus;
        }
        return false;
    }

    bool is_browser_closed()
    {
        if (m_client)
        {
            return m_client->m_closed;
        }
        return true;
    }

    CefRefPtr<CefBrowser> get_browser()
    {
        if (m_client)
        {
            return m_client->m_browser;
        }
        return nullptr;
    }

    void update_render_handler_dimensions(int width, int height, int pixel_density)
    {
        if (m_client && m_client->m_render_handler)
        {
            m_client->m_render_handler->UpdateDimensions(width, height, pixel_density);
        }
    }

    void request_new_frame()
    {
        if (m_client)
        {
            // std::cout << "request new frame" << std::endl;
            m_client->request_new_frame();
        }
    }

    void copy() {
        if (m_client) {
            m_client->copy();
        }
    }

    void cut() {
        std::cout << "Cut called from MyApp" << std::endl;
        if (m_client) {
            m_client->cut();
        }
    }

    void paste() {
        if (m_client) {
            m_client->paste();
        }
    }

    void undo() {
        if (m_client) {
            m_client->undo();
        }
    }

    void redo() {
        if (m_client) {
            m_client->redo();
        }
    }

    void select_all() {
        if (m_client) {
            m_client->select_all();
        }
    }

    // Context menu methods
    bool should_show_context_menu() {
        return m_client && m_client->m_show_context_menu;
    }

    void hide_context_menu() {
        if (m_client) {
            m_client->m_show_context_menu = false;
        }
    }

    bool render_context_menu() {
        if (!m_client || !m_client->m_show_context_menu) {
            return false;
        }

        bool menu_clicked = false;
        
        // Set the next window position to where the context menu should appear
        ImGui::SetNextWindowPos(ImVec2(m_client->m_context_menu_x, m_client->m_context_menu_y), 
                               ImGuiCond_Always);
        
        if (ImGui::BeginPopup("ContextMenu")) {
            for (const auto& item : m_client->m_context_menu_items) {
                if (item.first == -1) {
                    // Separator
                    if (!item.second.empty()) {
                        ImGui::Separator();
                    }
                } else {
                    if (ImGui::MenuItem(item.second.c_str())) {
                        // Execute the context menu command
                        switch (item.first) {
                            case 1001: undo(); break;
                            case 1002: redo(); break;
                            case 1003: 
                            std::cout << "Context menu cut selected" << std::endl;
                            cut(); 
                            break;
                            case 1004: copy(); break;
                            case 1005: paste(); break;
                            case 1006: 
                                if (m_client) m_client->delete_selection(); 
                                break;
                            case 1007: select_all(); break;
                        }
                        menu_clicked = true;
                        m_client->m_show_context_menu = false;
                    }
                }
            }
            ImGui::EndPopup();
        }
        
        return menu_clicked;
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

    void inject_ime_commit_text(const std::string &text, const CefRange &range, int relative_cursor_pos)
    {
        if (m_client && m_client->get_browser() && m_client->get_browser()->IsValid())
        {
            m_client->get_browser()->GetHost()->ImeCommitText(text, range, relative_cursor_pos);
        }
    }

    void inject_ime_set_composition(const std::string &text,
                                    const std::vector<CefCompositionUnderline> &underlines,
                                    const CefRange &replacement_range,
                                    const CefRange &selection_range)
    {
        if (m_client && m_client->get_browser() && m_client->get_browser()->IsValid())
        {
            m_client->get_browser()->GetHost()->ImeSetComposition(text, underlines, replacement_range, selection_range);
        }
    }

    void inject_ime_finish_composing_text(bool keep_selection)
    {
        if (m_client && m_client->get_browser() && m_client->get_browser()->IsValid())
        {
            m_client->get_browser()->GetHost()->ImeFinishComposingText(keep_selection);
        }
    }

    void inject_ime_cancel_composition()
    {
        if (m_client && m_client->get_browser() && m_client->get_browser()->IsValid())
        {
            m_client->get_browser()->GetHost()->ImeCancelComposition();
        }
    }

    void OnBeforeCommandLineProcessing(const CefString &process_type,
                                       CefRefPtr<CefCommandLine> command_line) override;

    void encode_render_command(MTL::RenderCommandEncoder *render_command_encoder);

    // This is the magic hook provided by CEF, with the correct name.
    void OnScheduleMessagePumpWork(int64_t delay_ms) override;

    void update_geometry(int holeX, int holeY, int holeWidth, int holeHeight, int viewportWidth, int viewportHeight);

private:
    IMPLEMENT_REFCOUNTING(MyApp);
};

#endif // MYCEF_H
