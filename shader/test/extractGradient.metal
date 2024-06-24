//
//  common_gradient.metal
//  SportsCoach
//
//  Created by wesley on 2024/6/22.
//

#include <metal_stdlib>
using namespace metal;

constant int8_t sobelX[9] = {-1, 0, 1,
        -2, 0, 2,
        -1, 0, 1};

constant int8_t sobelY[9] = {-1, -2, -1,
        0,  0,  0,
        1,  2,  1};

kernel void spacetimeGradientExtraction(
                                        device uchar* grayBufferPre [[buffer(0)]],
                                        device uchar* grayBufferCur [[buffer(1)]],
                                        device short* outGradientX [[buffer(2)]],
                                        device short* outGradientY [[buffer(3)]],
                                        device uchar* outGradientT [[buffer(4)]],
                                        constant uint &width [[buffer(5)]],
                                        constant uint &height [[buffer(6)]],
                                        uint2 gid [[thread_position_in_grid]])
{
        int idx = gid.y * width + gid.x;
        uchar diff = abs(grayBufferCur[idx] - grayBufferPre[idx]);
        outGradientT[idx] = diff;
        
        if (gid.x == 0 || gid.x >= width - 1 || gid.y == 0 || gid.y >= height - 1) return;
        
        short gradientX = 0.0, gradientY = 0.0;
        
        idx = 0;
        for (int j = -1; j <= 1; j++) {
                for (int i = -1; i <= 1; i++) {
                        uint index = (gid.y + j) * width + (gid.x + i);
                        float gray = short(grayBufferPre[index]);
                        gradientX += gray * sobelX[idx];
                        gradientY += gray * sobelY[idx];
                        idx++;
                }
        }
        
        outGradientX[gid.y * width + gid.x] = gradientX;
        outGradientY[gid.y * width + gid.x] = gradientY;
}
