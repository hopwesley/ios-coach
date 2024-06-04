#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 顶点着色器
vertex VertexOut basic_vertex(const device float4* vertexArray [[ buffer(0) ]],
                              uint vertexID [[ vertex_id ]]) {
    VertexOut out;
    out.position = vertexArray[vertexID];
    out.texCoord = (vertexArray[vertexID].xy + 1.0) * 0.5; // 将坐标转换为 [0, 1] 范围
    return out;
}

// 片元着色器
fragment half4 basic_fragment(VertexOut in [[ stage_in ]],
                              texture2d<float> inTexture [[ texture(0) ]],
                              sampler textureSampler [[ sampler(0) ]]) {
    float gray = inTexture.sample(textureSampler, in.texCoord).r;
    return half4(gray, gray, gray, 1.0);
}

kernel void add_arrays(device const float* inA,
                       device const float* inB,
                       device float* result,
                       uint index [[thread_position_in_grid]])
{
    // the for-loop is replaced with a collection of threads, each of which
    // calls this function.
    result[index] = inA[index] + inB[index];
}
