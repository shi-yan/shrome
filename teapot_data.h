#ifndef TEAPOT_DATA_H
#define TEAPOT_DATA_H

#include <simd/simd.h>


inline float verticalOffset(simd::float2 accumulatedHeightPageIndex, float displayScale) {
    return accumulatedHeightPageIndex.x * displayScale + accumulatedHeightPageIndex.y * 10.0;
}

struct TeapotVertexData {
    simd::float3 position;
    simd::float3 normal;
};

struct FlameVertexData {
    simd::float3 position;
    simd::float3 normal;
    simd::float2 uv;
};

struct TransformationDataWithNormal {
    simd::float4x4 modelView;
    simd::float4x4 projection;
    simd::float4x4 normal;
};

struct PhongMaterial {
    simd::float4 ambientColor;
    simd::float4 diffuseColor;
    simd::float4 specularColor;
    float shininess;
};

#endif