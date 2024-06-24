//
//  TimeGradient.metal
//  SportsCoach
//
//  Created by wesley on 2024/6/18.
//

#include <metal_stdlib>
using namespace metal;

#include <metal_stdlib>
using namespace metal;

kernel void absDiffKernel(device uchar *grayFrameA [[buffer(0)]],
                          device uchar *grayFrameB [[buffer(1)]],
                          device uchar *outputBuffer [[buffer(2)]],
                          constant uint &width [[buffer(3)]],
                          constant uint &height [[buffer(4)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    uint index = gid.y * width + gid.x;
    uchar gray1 = grayFrameA[index];
    uchar gray2 = grayFrameB[index];

    uchar diff = abs(gray1 - gray2);

    outputBuffer[index] = diff;
}

