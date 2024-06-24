//
//  alignVideo.metal
//  SportsCoach
//
//  Created by wesley on 2024/6/24.
//

#include <metal_stdlib>
using namespace metal;

kernel void sumQuantizedGradients(
                                  device float* avgGradientOneFrame [[buffer(0)]],
                                  device float* finalGradient [[buffer(1)]],
                                  constant uint &numBlocks [[buffer(2)]],
                                  uint gid [[thread_position_in_grid]])
{
        if (gid >= 10) return;
        
        float sum = 0.0;
        for (uint i = 0; i < numBlocks; ++i) {
                sum += avgGradientOneFrame[i * 10 + gid];
        }
        finalGradient[gid] = sum;
}
