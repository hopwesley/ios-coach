#include <metal_stdlib>
using namespace metal;

kernel void spatialGradientKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                  device float *outGradientX [[buffer(0)]],
                                  device float *outGradientY [[buffer(1)]],
                                  uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;

    float gray = inTexture.read(uint2(gid)).r;

    // 计算梯度
    float gradientX = 0.0;
    float gradientY = 0.0;

    if (gid.x + 1 < inTexture.get_width()) {
        gradientX = gray - inTexture.read(uint2(gid.x + 1, gid.y)).r;
    }

    if (gid.y + 1 < inTexture.get_height()) {
        gradientY = gray - inTexture.read(uint2(gid.x, gid.y + 1)).r;
    }

    outGradientX[gid.y * inTexture.get_width() + gid.x] = gradientX;
    outGradientY[gid.y * inTexture.get_width() + gid.x] = gradientY;
}

kernel void sobelGradientKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                device float *outGradientX [[buffer(0)]],
                                device float *outGradientY [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inTexture.get_width() - 1 || gid.y >= inTexture.get_height() - 1 || gid.x == 0 || gid.y == 0) return;

    float sobelX[9] = {-1, 0, 1,
                       -2, 0, 2,
                       -1, 0, 1};

    float sobelY[9] = {-1, -2, -1,
                        0,  0,  0,
                        1,  2,  1};

    float gradientX = 0.0;
    float gradientY = 0.0;

    int idx = 0;
    for (int i = -1; i <= 1; ++i) {
        for (int j = -1; j <= 1; ++j) {
            float gray = inTexture.read(uint2(gid.x + i, gid.y + j)).r;
            gradientX += gray * sobelX[idx];
            gradientY += gray * sobelY[idx];
            idx++;
        }
    }

    outGradientX[gid.y * inTexture.get_width() + gid.x] = gradientX;
    outGradientY[gid.y * inTexture.get_width() + gid.x] = gradientY;
}
