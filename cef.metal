
#include <metal_stdlib>

using namespace metal;


struct VertexOutput
{
    float4 clip_position [[position]];
    float2 uv;
};

vertex VertexOutput
cefVertexShader(uint vertexID [[vertex_id]],
                                            constant float4 *position [[buffer(0)]])
{
    VertexOutput out;

    out.clip_position =   float4(position[vertexID][0], position[vertexID][1],0.0,1.0);

    out.uv = float2( position[vertexID][2], position[vertexID][3]);
    return out;
}

fragment float4 cefFragmentShader(VertexOutput in [[stage_in]],
   texture2d< float, access::sample > tex [[texture(0)]])
{
    constexpr sampler s( address::repeat, filter::linear );
    float3 texel = tex.sample( s, in.uv ).rgb;
    return float4(texel.x, texel.y, texel.z, 1.0f);
}

// Popup shader with projection matrix
vertex VertexOutput
cefPopupVertexShader(uint vertexID [[vertex_id]],
                     constant float4 *position [[buffer(0)]],
                     constant float2 &offset [[buffer(2)]],
                     constant float4x4 &projection [[buffer(3)]])
{
    VertexOutput out;

    // Apply offset to position (position is in pixel coordinates)
    float2 pixel_pos = float2(position[vertexID][0], position[vertexID][1]) + offset;

    // Transform to NDC using projection matrix
    out.clip_position = projection * float4(pixel_pos, 0.0, 1.0);

    out.uv = float2(position[vertexID][2], position[vertexID][3]);
    return out;
}