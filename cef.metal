
#include <metal_stdlib>

using namespace metal;


struct VertexOutput
{
    float4 clip_position [[position]];
    float2 uv;
};

vertex VertexOutput
cefVertexShader(uint vertexID [[vertex_id]],
                                            constant float4 *position [[buffer(0)]],
                                            constant float4x4 &uProjection [[buffer(1)]],
                                            constant float2 &offset [[buffer(2)]])
{
    VertexOutput out;

    out.clip_position = uProjection * float4(position[vertexID][0] + offset.x,position[vertexID][1]+offset.y,0.0,1.0);

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