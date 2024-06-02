#include <metal_stdlib>
using namespace metal;

// 顶点着色器
vertex float4 basic_vertex(const device float4* vertexArray [[ buffer(0) ]],
                           uint vertexID [[ vertex_id ]]) {
    return vertexArray[vertexID];
}

// 片元着色器
fragment half4 basic_fragment(texture2d<float> inTexture [[ texture(0) ]],
                              sampler textureSampler [[ sampler(0) ]],
                              float4 fragCoord [[ position ]]) {
    float gray = inTexture.sample(textureSampler, fragCoord.xy / 256.0).r;
    return half4(gray, gray, gray, 1.0);
}
