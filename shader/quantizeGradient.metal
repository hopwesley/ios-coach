//
//  quantizeGradient.metal
//  SportsCoach
//
//  Created by wesley on 2024/6/18.
//

#include <metal_stdlib>
using namespace metal;

constant float threshold = 1.29107;

kernel void computeGradientProjections(
                                       device const short *gradientX [[ buffer(0) ]],
                                       device const short *gradientY [[ buffer(1) ]],
                                       device const uchar *gradientT [[ buffer(2) ]],
                                       device float *outputQ [[ buffer(3) ]],
                                       constant float3 *P [[ buffer(4) ]],
                                       constant uint &width [[ buffer(5) ]],
                                       constant uint &height [[ buffer(6) ]],
                                       uint2 gid [[ thread_position_in_grid ]]
                                       )
{
        if (gid.x >= width || gid.y >= height) {
                return;
        }
        
        uint index = gid.y * width + gid.x;
        
        // 计算梯度向量 g_i
        float3 g = float3(float(gradientX[index]), float(gradientY[index]), float(gradientT[index]));
        
        // 计算 g_i 的 L2 范数并归一化
        float g_l2_norm = length(g);
        if (g_l2_norm == 0.0) {
                for (int i = 0; i < 10; ++i) {
                        outputQ[index * 10 + i] = 0.0;
                }
                return;
        }
        float3 g_normalized = g / g_l2_norm;
        
        float q_prime[10];         // 计算投影结果 q_i
        for (int i = 0; i < 10; ++i) {
                float bin_i = dot(P[i], g_normalized);
                float bin_j = dot(P[i+10], g_normalized);
                q_prime[i] = fabs(bin_i) + fabs(bin_j) - threshold;
                q_prime[i] = max(q_prime[i], 0.0);
        }
        
        // 计算 q_prime 的 L2 范数
        float q_prime_l2_norm = 0.0;
        for (int i = 0; i < 10; ++i) {
                q_prime_l2_norm += q_prime[i] * q_prime[i];
        }
        q_prime_l2_norm = sqrt(q_prime_l2_norm);
        if (q_prime_l2_norm == 0.0) {
                for (int i = 0; i < 10; ++i) {
                        outputQ[index * 10 + i] = 0.0;
                }
                return;
        }
        
        // 分布梯度大小到阈值后的直方图
        for (int i = 0; i < 10; ++i) {
                outputQ[index * 10 + i] = (g_l2_norm * q_prime[i]) / q_prime_l2_norm;
        }
}
