#define NS_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#include <Foundation/Foundation.hpp>
#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <simd/simd.h>
#include "mycef.h"
#include <dispatch/dispatch.h>
#include <iostream>
#include <include/cef_id_mappers.h>

MyApp::MyApp(MTL::Device *metal_device, uint32_t window_width, uint32_t window_height, uint32_t pixel_density)
    : m_metal_device(metal_device),
      m_window_width(window_width),
      m_window_height(window_height),
      m_pixel_density(pixel_density)
{
    // Initialize any necessary resources here, such as creating a Metal texture.
    // For example:
    // texture = m_metal_device->newTexture(...);

    m_popup_show_callback = [this](bool show)
    {
        std::cout << "should show call back" << std::endl;
        m_should_show_popup = show;
    };

    m_popup_sized_callback = [this](const CefRect &rect)
    {
        m_popup_pos = rect;
        simd::float2 offset = {m_popup_pos.x, m_popup_pos.y};

        if (m_popup_offset_buffer == nullptr)
        {
            m_popup_offset_buffer = m_metal_device->newBuffer(sizeof(simd::float2), MTL::ResourceStorageModeShared);
        }
        memcpy(m_popup_offset_buffer->contents(), &offset, sizeof(simd::float2));
        std::cout << "should show popup size " << m_popup_pos.width << ", " << m_popup_pos.height << std::endl;

        simd::float4 quad_vertices[] = {
            {0.0f, 0.0f, 0.0f, 0.0f},
            {0.0f, m_popup_pos.height, 0.0f, 1.0f},
            {m_popup_pos.width, 0.0f, 1.0f, 0.0f},
            {m_popup_pos.width, m_popup_pos.height, 1.0f, 1.0f}};
        if (!m_popup_triangle_vertex_buffer)
        {
            m_popup_triangle_vertex_buffer = m_metal_device->newBuffer(&quad_vertices,
                                                                       sizeof(quad_vertices),
                                                                       MTL::ResourceStorageModeShared);
        }
        else
        {
            memcpy(m_popup_triangle_vertex_buffer->contents(), &offset, sizeof(quad_vertices));
        }
    };

    m_on_accelerated_texture_ready = [this](CefRenderHandler::PaintElementType type,
                                            const CefRenderHandler::RectList &dirtyRects,
                                            IOSurfaceRef io_surface)
    {
        size_t width = IOSurfaceGetWidth(io_surface);
        size_t height = IOSurfaceGetHeight(io_surface);

        if (type == CefRenderHandler::PaintElementType::PET_VIEW)
        {
            if (m_texture && ((m_texture_width != static_cast<uint32_t>(width) || m_texture_height != static_cast<uint32_t>(height)) ||
                              m_texture->iosurface() != io_surface))
            {
                m_texture->release();
                m_texture = nullptr;
            }

            if (!m_texture)
            {
                m_window_width = width;
                m_window_height = height;
                m_texture_width = m_window_width;
                m_texture_height = m_window_height;

                MTL::TextureDescriptor *descriptor = MTL::TextureDescriptor::texture2DDescriptor(
                    MTL::PixelFormatBGRA8Unorm,
                    width,
                    height,
                    false // mipmapped
                );

                // Set the usage and storage mode.
                descriptor->setUsage(MTL::ResourceUsageSample | MTL::ResourceUsageRead);
                descriptor->setStorageMode(MTL::StorageModeManaged);

                // The key function: Create the texture directly from the IOSurface.
                // This creates a Metal texture that aliases the memory of the IOSurface.
                m_texture = m_metal_device->newTexture(descriptor, io_surface, 0);

                // descriptor->release(); // no need to release
            }
        }
        else if (type == CefRenderHandler::PaintElementType::PET_POPUP && m_should_show_popup)
        {
            if (m_popup_texture && ((m_popup_texture_width != static_cast<uint32_t>(width) || m_popup_texture_height != static_cast<uint32_t>(height)) ||
                                  m_popup_texture->iosurface() != io_surface))
            {
                m_popup_texture->release();
                m_popup_texture = nullptr;
            }

            if (!m_popup_texture)
            {
                m_popup_texture_width = width;
                m_popup_texture_height = height;

                MTL::TextureDescriptor *descriptor = MTL::TextureDescriptor::texture2DDescriptor(
                    MTL::PixelFormatBGRA8Unorm,
                    width,
                    height,
                    false // mipmapped
                );

                // Set the usage and storage mode.
                descriptor->setUsage(MTL::ResourceUsageSample | MTL::ResourceUsageRead);
                descriptor->setStorageMode(MTL::StorageModeManaged);

                // Create the popup texture directly from the IOSurface.
                m_popup_texture = m_metal_device->newTexture(descriptor, io_surface, 0);
            }
        }
    };

    m_on_texture_ready = [this](CefRenderHandler::PaintElementType type, const CefRenderHandler::RectList &dirtyRects, const void *buffer, int width, int height)
    {
        // std::cout << "texture ready " << width << ", " << height << std::endl;
        if (type == CefRenderHandler::PaintElementType::PET_VIEW)
        {
            if (m_texture && (m_texture_width != static_cast<uint32_t>(width) || m_texture_height != static_cast<uint32_t>(height)))
            {
                m_texture->release();
                m_texture = nullptr;
            }
            bool full_update = false;
            if (!m_texture)
            {
                m_window_width = width;
                m_window_height = height;
                m_texture_width = m_window_width;
                m_texture_height = m_window_height;
                // std::cout << "recreate texture " << m_texture_width << ", " << m_texture_height << std::endl;
                MTL::TextureDescriptor *pTextureDesc = MTL::TextureDescriptor::alloc()->init();
                pTextureDesc->setWidth(m_window_width);
                pTextureDesc->setHeight(m_window_height);
                pTextureDesc->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
                pTextureDesc->setTextureType(MTL::TextureType2D);
                pTextureDesc->setStorageMode(MTL::StorageModeManaged);
                pTextureDesc->setUsage(MTL::ResourceUsageSample | MTL::ResourceUsageRead);

                m_texture = m_metal_device->newTexture(pTextureDesc);

                pTextureDesc->release();
                full_update = true;
            }

            if (m_texture)
            {
                if (full_update)
                {
                    size_t bitmap_stride = width * 4; // Assuming 4 bytes per pixel (BGRA format)

                    // std::cout << "full texture update width " << width << ", height " << height << std::endl;
                    //   Replace the region with the new data
                    m_texture->replaceRegion(MTL::Region(0, 0, 0, width, height, 1), 0, buffer, bitmap_stride);
                }
                else
                {
                    // This bytesPerRow is correct for the overall buffer provided by OnPaint
                    NS::UInteger bytesPerRow = width * 4; // Assuming 4 bytes per pixel (BGRA format)
                    // std::cout << "partial texture update for " << dirtyRects.size() << " rects" << std::endl;
                    for (const auto &rect : dirtyRects)
                    {
                        // Calculate the region to replace on the Metal texture
                        MTL::Region region = MTL::Region(rect.x, rect.y, 0, rect.width, rect.height, 1);

                        // *******************************************************************
                        // CRITICAL FIX: Calculate the byte offset into the 'buffer' for this specific rect
                        // The buffer starts at (0,0) of the overall image.
                        // To get to the start of 'rect', you move down 'rect.y' rows, and then
                        // move right 'rect.x' columns within that row.
                        // Each pixel is 4 bytes (BGRA).
                        // *******************************************************************
                        const uint8_t *rectBufferStart = static_cast<const uint8_t *>(buffer) +
                                                         (rect.y * bytesPerRow) +
                                                         (rect.x * 4); // 4 bytes per pixel

                        // Replace the region with the data starting at 'rectBufferStart'
                        m_texture->replaceRegion(region, 0, rectBufferStart, bytesPerRow);
                        // Note: bytesPerRow passed to replaceRegion is the stride of the *source* buffer,
                        // which in this case is the width of the full image.
                    }
                }
            }
        }
        else if (type == CefRenderHandler::PaintElementType::PET_POPUP && m_should_show_popup)
        {
            if (m_popup_texture && (m_popup_texture_width != static_cast<uint32_t>(width) || m_popup_texture_height != static_cast<uint32_t>(height)))
            {
                m_popup_texture->release();
                m_popup_texture = nullptr;
            }
            bool full_update = false;
            if (!m_popup_texture)
            {
                m_popup_texture_width = width;
                m_popup_texture_height = height;
                // std::cout << "recreate texture " << m_texture_width << ", " << m_texture_height << std::endl;
                MTL::TextureDescriptor *pTextureDesc = MTL::TextureDescriptor::alloc()->init();
                pTextureDesc->setWidth(m_popup_texture_width);
                pTextureDesc->setHeight(m_popup_texture_height);
                pTextureDesc->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
                pTextureDesc->setTextureType(MTL::TextureType2D);
                pTextureDesc->setStorageMode(MTL::StorageModeManaged);
                pTextureDesc->setUsage(MTL::ResourceUsageSample | MTL::ResourceUsageRead);

                m_popup_texture = m_metal_device->newTexture(pTextureDesc);

                pTextureDesc->release();
                full_update = true;
            }

            if (m_popup_texture)
            {
                if (full_update)
                {
                    size_t bitmap_stride = width * 4; // Assuming 4 bytes per pixel (BGRA format)

                    // std::cout << "width " << width << ", height " << height << std::endl;
                    //  Replace the region with the new data
                    m_popup_texture->replaceRegion(MTL::Region(0, 0, 0, width, height, 1), 0, buffer, bitmap_stride);
                }
                else
                {
                    // This bytesPerRow is correct for the overall buffer provided by OnPaint
                    NS::UInteger bytesPerRow = width * 4; // Assuming 4 bytes per pixel (BGRA format)

                    for (const auto &rect : dirtyRects)
                    {
                        // Calculate the region to replace on the Metal texture
                        MTL::Region region = MTL::Region(rect.x, rect.y, 0, rect.width, rect.height, 1);

                        // *******************************************************************
                        // CRITICAL FIX: Calculate the byte offset into the 'buffer' for this specific rect
                        // The buffer starts at (0,0) of the overall image.
                        // To get to the start of 'rect', you move down 'rect.y' rows, and then
                        // move right 'rect.x' columns within that row.
                        // Each pixel is 4 bytes (BGRA).
                        // *******************************************************************
                        const uint8_t *rectBufferStart = static_cast<const uint8_t *>(buffer) +
                                                         (rect.y * bytesPerRow) +
                                                         (rect.x * 4); // 4 bytes per pixel

                        // Replace the region with the data starting at 'rectBufferStart'
                        m_popup_texture->replaceRegion(region, 0, rectBufferStart, bytesPerRow);
                        // Note: bytesPerRow passed to replaceRegion is the stride of the *source* buffer,
                        // which in this case is the width of the full image.
                    }
                }
            }
        }
    };
}

void MyApp::OnBeforeCommandLineProcessing(const CefString &process_type, CefRefPtr<CefCommandLine> command_line)
{
    // std::cout << "OnBeforeCommandLineProcessing called for process type: " << process_type.ToString() << std::endl;
    // Check if it's the browser process (process_type will be empty for browser process)
    if (process_type.empty())
    {
        command_line->AppendSwitch("enable-beginframe-scheduling");
        command_line->AppendSwitch("use-mock-keychain");
        // Add other browser process specific switches here.
        // For WebGPU/WebGL, remember NOT to use --disable-gpu or --disable-gpu-compositing.
    }
    // You can also add switches for specific process types if needed:
    // else if (process_type == "renderer") {
    //     // Add renderer process specific switches
    // }
}

void MyApp::update_geometry(int holeX, int holeY, int holeWidth, int holeHeight, int viewportWidth, int viewportHeight)
{
    if (m_triangle_vertex_buffer)
    {
        std::cout << "update geometry " << holeX << ", " << holeY << ", " << holeWidth << ", " << holeHeight << std::endl;
        float left = holeX / (float)viewportWidth * 2.0f - 1.0f;
        float right = (holeX + holeWidth) / (float)viewportWidth * 2.0f - 1.0f;
        float top = holeY / (float)viewportHeight * 2.0f - 1.0f;
        float bottom = (holeY + holeHeight) / (float)viewportHeight * 2.0f - 1.0f;

        simd::float4 quad_vertices[] = {
            {left, top, 0.0f, 1.0f},
            {left, bottom, 0.0f, 0.0f},
            {right, top, 1.0f, 1.0f},
            {right, bottom, 1.0f, 0.0f}};

        memcpy(m_triangle_vertex_buffer->contents(), &quad_vertices, sizeof(quad_vertices));
    }
}

MyApp::~MyApp()
{
    // Clean up resources if necessary
    if (m_texture)
    {
        m_texture->release();
        m_texture = nullptr;
    }

    if (m_depth_stencil_state_disabled)
    {
        m_depth_stencil_state_disabled->release();
        m_depth_stencil_state_disabled = nullptr;
    }

    if (m_render_pipeline)
    {
        m_render_pipeline->release();
        m_render_pipeline = nullptr;
    }
    if (m_popup_offset_buffer)
    {
        m_popup_offset_buffer->release();
        m_popup_offset_buffer = nullptr;
    }

    if (m_popup_texture)
    {
        m_popup_texture->release();
        m_popup_texture = nullptr;
    }

    if (m_triangle_vertex_buffer)
    {
        m_triangle_vertex_buffer->release();
        m_triangle_vertex_buffer = nullptr;
    }

    if (m_popup_triangle_vertex_buffer)
    {
        m_popup_triangle_vertex_buffer->release();
        m_popup_triangle_vertex_buffer = nullptr;
    }
}

MyRenderHandler::MyRenderHandler(bool accelerated_rendering, int width, int height, int pixel_density,
                                 RenderingCallback rendering_callback,
                                 AcceleratedRenderingCallback accelerated_rendering_callback,
                                 PopupShowCallback popup_show_callback,
                                 PopupSizedCallback popup_sized_callback)
    : m_accelerated_rendering(accelerated_rendering),
      m_width(width), m_height(height), m_pixel_density(pixel_density),
      m_rendering_callback(rendering_callback),
      m_accelerated_rendering_callback(accelerated_rendering_callback),
      m_popup_show_callback(popup_show_callback),
      m_popup_sized_callback(popup_sized_callback)
{
    std::cout << "MyRenderHandler" << m_width << ", " << m_height << ", " << m_pixel_density << std::endl;
}

void MyRenderHandler::UpdateDimensions(int width, int height, int pixel_density)
{
    m_width = width;
    m_height = height;
    m_pixel_density = pixel_density;
    // std::cout << "MyRenderHandler updated dimensions: " << m_width << ", " << m_height << ", " << m_pixel_density << std::endl;
}

void MyApp::init(MTL::Device *metal_device, uint64_t pixel_format, uint32_t window_width, uint32_t window_height)
{
    m_metal_device = metal_device;
    m_window_width = window_width;
    m_window_height = window_height;

    simd::float4 quad_vertices[] = {
        {-1.0f, -1.0f, 0.0f, 1.0f},
        {-1.0f, 1.0f, 0.0f, 0.0f},
        {1.0f, -1.0f, 1.0f, 1.0f},
        {1.0f, 1.0f, 1.0f, 0.0f}};

    m_triangle_vertex_buffer = m_metal_device->newBuffer(&quad_vertices,
                                                         sizeof(quad_vertices),
                                                         MTL::ResourceStorageModeShared);

    // Initialize the texture or any other resources as needed
    if (m_texture)
    {
        m_texture->release();
        m_texture = nullptr;
    }

    m_texture_width = window_width;
    m_texture_height = window_height;
    // std::cout << "create texture " << m_texture_width << ", " << m_texture_height << std::endl;
    MTL::TextureDescriptor *pTextureDesc = MTL::TextureDescriptor::alloc()->init();
    pTextureDesc->setWidth(m_window_width);
    pTextureDesc->setHeight(m_window_height);
    pTextureDesc->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    pTextureDesc->setTextureType(MTL::TextureType2D);
    pTextureDesc->setStorageMode(MTL::StorageModeManaged);
    pTextureDesc->setUsage(MTL::ResourceUsageSample | MTL::ResourceUsageRead);

    m_texture = m_metal_device->newTexture(pTextureDesc);

    pTextureDesc->release();

    MTL::DepthStencilDescriptor *ds_desc_disabled = MTL::DepthStencilDescriptor::alloc()->init();
    ds_desc_disabled->setDepthCompareFunction(MTL::CompareFunctionAlways); // Or whatever your depth test needs
    ds_desc_disabled->setDepthWriteEnabled(false);                         // Disable depth writes if not needed

    // Set up stencil behavior
    MTL::StencilDescriptor *front_stencil_disabled = MTL::StencilDescriptor::alloc()->init();
    front_stencil_disabled->setStencilCompareFunction(MTL::CompareFunctionAlways);   // Like gl.stencilFunc(ALWAYS)
    front_stencil_disabled->setStencilFailureOperation(MTL::StencilOperationKeep);   // KEEP
    front_stencil_disabled->setDepthFailureOperation(MTL::StencilOperationKeep);     // KEEP
    front_stencil_disabled->setDepthStencilPassOperation(MTL::StencilOperationKeep); // REPLACE on depth+stencil pass
    front_stencil_disabled->setReadMask(0xFF);
    front_stencil_disabled->setWriteMask(0x00);

    ds_desc_disabled->setFrontFaceStencil(front_stencil_disabled);
    ds_desc_disabled->setBackFaceStencil(front_stencil_disabled); // Same for back face in this case
    front_stencil_disabled->release();
    m_depth_stencil_state_disabled = metal_device->newDepthStencilState(ds_desc_disabled);
    ds_desc_disabled->release();

    MTL::Library *metal_default_library = metal_device->newDefaultLibrary();
    if (!metal_default_library)
    {
        std::cerr << "Failed to load default library." << std::endl;
        std::exit(-1);
    }

    MTL::Function *vertex_shader = metal_default_library->newFunction(NS::String::string("cefVertexShader", NS::ASCIIStringEncoding));
    assert(vertex_shader);
    MTL::Function *fragment_shader = metal_default_library->newFunction(NS::String::string("cefFragmentShader", NS::ASCIIStringEncoding));
    assert(fragment_shader);

    MTL::RenderPipelineDescriptor *render_pipeline_descriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    render_pipeline_descriptor->setLabel(NS::String::string("Triangle Rendering Pipeline", NS::ASCIIStringEncoding));
    render_pipeline_descriptor->setVertexFunction(vertex_shader);
    render_pipeline_descriptor->setFragmentFunction(fragment_shader);
    assert(render_pipeline_descriptor);
    render_pipeline_descriptor->colorAttachments()->object(0)->setPixelFormat(static_cast<MTL::PixelFormat>(pixel_format));

    NS::Error *error;
    m_render_pipeline = metal_device->newRenderPipelineState(render_pipeline_descriptor, &error);

    render_pipeline_descriptor->release();
    vertex_shader->release();
    fragment_shader->release();
    metal_default_library->release();

    std::cout << "Render pipeline state created successfully." << std::endl;
}

void MyApp::encode_render_command(MTL::RenderCommandEncoder *render_command_encoder)
{
    if (m_texture)
    {
        render_command_encoder->setRenderPipelineState(m_render_pipeline);
        render_command_encoder->setDepthStencilState(m_depth_stencil_state_disabled);
        render_command_encoder->setVertexBuffer(m_triangle_vertex_buffer, 0, 0);
        render_command_encoder->setCullMode(MTL::CullMode::CullModeNone);
        render_command_encoder->setFragmentTexture(m_texture, /* index */ 0);
        NS::UInteger vertexStart = 0;
        NS::UInteger vertexCount = 4;
        render_command_encoder->drawPrimitives(MTL::PrimitiveTypeTriangleStrip, vertexStart, vertexCount);
        // std::cout << "draw cef texture " << m_texture_width << ", " << m_texture_height << std::endl;
        if (m_should_show_popup && m_popup_texture && m_popup_triangle_vertex_buffer && m_popup_offset_buffer)
        {
            render_command_encoder->setVertexBuffer(m_popup_triangle_vertex_buffer, 0, 0);
            render_command_encoder->setVertexBuffer(m_popup_offset_buffer, 0, 2);
            render_command_encoder->setCullMode(MTL::CullMode::CullModeNone);
            render_command_encoder->setFragmentTexture(m_popup_texture, /* index */ 0);

            render_command_encoder->drawPrimitives(MTL::PrimitiveTypeTriangleStrip, vertexStart, vertexCount);
        }
    }
}

void MyClient::OnAfterCreated(CefRefPtr<CefBrowser> browser)
{
    std::cout << "m_browser assigned --- " << std::endl;
    m_browser = browser;
    if (m_browser->GetHost())
    {
        m_browser->GetHost()->WasResized();   // Initial resize notification
        m_browser->GetHost()->SetFocus(true); // Give focus
    }
}

bool MyClient::OnChromeCommand(CefRefPtr<CefBrowser> browser,
                               int command_id,
                               cef_window_open_disposition_t disposition)
{

    CEF_DECLARE_COMMAND_ID(IDC_CUT);
    CEF_DECLARE_COMMAND_ID(IDC_COPY);
    CEF_DECLARE_COMMAND_ID(IDC_PASTE);

    static const int kAllowedCommandIds[] = {
        IDC_CUT,
        IDC_COPY,
        IDC_PASTE};
    for (int kAllowedCommandId : kAllowedCommandIds)
    {
        if (command_id == kAllowedCommandId)
        {
            return true;
        }
    }

    return false;
}

std::string get_macos_cache_dir(const std::string &app_name)
{
    const char *home = getenv("HOME");
    if (!home)
        return "/tmp/" + app_name; // fallback
    return std::string(home) + "/Library/Caches/" + app_name;
}

void MyApp::OnScheduleMessagePumpWork(int64_t delay_ms)
{
    if (delay_ms <= 0)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
          //  std::cout << "OnScheduleMessagePumpWork called with delay: " << delay_ms << " ms" << std::endl;
          CefDoMessageLoopWork();
        });
    }
    else
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
                         CefDoMessageLoopWork();
                       });
    }
}
