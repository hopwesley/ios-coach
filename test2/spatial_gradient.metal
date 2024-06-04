#include <metal_stdlib>
using namespace metal;

kernel void spatial_gradient(texture2d<float, access::read> inTexture [[texture(0)]],
                             device float *outGradientX [[buffer(0)]],
                             device float *outGradientY [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;

    float2 texCoord = float2(gid) + 0.5; // 中心点
    float gray = inTexture.read(uint2(gid)).r;

    // 计算梯度
    float gradientX = gray - inTexture.read(uint2(gid) + uint2(1, 0)).r;
    float gradientY = gray - inTexture.read(uint2(gid) + uint2(0, 1)).r;

    outGradientX[gid.y * inTexture.get_width() + gid.x] = gradientX;
    outGradientY[gid.y * inTexture.get_width() + gid.x] = gradientY;
}
