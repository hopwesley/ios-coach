#include <metal_stdlib>
using namespace metal;

// 定义全局变量
constant uint DescriptorParam_M = 2;
constant uint DescriptorParam_m = 4;
constant float threshold = 1.29107;

inline float q_prime_l2_norm(float q_prime[10]) {
        float norm = 0.0;
        for (int i = 0; i < 10; ++i) {
                norm += q_prime[i] * q_prime[i];
        }
        return sqrt(norm);
}

void quantizeGradientOfBlock(
                             float3 g,
                             constant float3 *P,
                             device float *outputQ,
                             uint index)
{
        // 计算 g 的 L2 范数并归一化
        float g_l2_norm = length(g);
        if (g_l2_norm == 0.0) {
                return;
        }
        float3 g_normalized = g / g_l2_norm;
        
        float q_prime[10];  // 计算投影结果 q_i
        for (int i = 0; i < 10; ++i) {
                float bin_i = dot(P[i], g_normalized);
                float bin_j = dot(P[i+10], g_normalized);
                q_prime[i] = fabs(bin_i) + fabs(bin_j) - threshold;
                q_prime[i] = max(q_prime[i], 0.0);
        }
        
        float q_prime_l2_len = q_prime_l2_norm(q_prime);
        if (q_prime_l2_len == 0.0) {
                return;
        }
        
        for (int i = 0; i < 10; ++i) {
                outputQ[index * 10 + i] = (g_l2_norm * q_prime[i]) / q_prime_l2_len;
        }
}


kernel void averageGradientOfAllBlock(
                                      device const short *gradientX [[ buffer(0) ]],
                                      device const short *gradientY [[ buffer(1) ]],
                                      device const uchar *gradientT [[ buffer(2) ]],
                                      device float *outputQ [[ buffer(3) ]],
                                      constant float3 *P [[ buffer(4) ]],
                                      constant uint &width [[ buffer(5) ]],
                                      constant uint &height [[ buffer(6) ]],
                                      constant uint &blockSize [[ buffer(7) ]],
                                      uint2 gid [[ thread_position_in_grid ]]
                                      )
{
        // 计算当前线程负责的区域的起始坐标
        uint blockStartX = gid.x * blockSize;
        uint blockStartY = gid.y * blockSize;
        
        // 确保不超出图像边界
        if (blockStartX >= width || blockStartY >= height) {
                return;
        }
        
        // 计算当前线程负责的区域内的平均时空梯度
        float3 sumGradient = float3(0.0, 0.0, 0.0);
        int count = 0;
        
        for (uint y = blockStartY; y < blockStartY + blockSize && y < height; ++y) {
                for (uint x = blockStartX; x < blockStartX + blockSize && x < width; ++x) {
                        uint index = y * width + x;
                        sumGradient += float3(float(gradientX[index]), float(gradientY[index]), float(gradientT[index]));
                        count++;
                }
        }
//        printf("Block (%d, %d): sumGradient = (%f, %f, %f)\n", gid.x, gid.y, sumGradient.x, sumGradient.y, sumGradient.z);
        
        if (count > 0) {
                sumGradient /= float(count);
        }
        
        // 调用量化梯度计算函数
        uint numBlocksX = (width + blockSize - 1) / blockSize;
        uint avgIndex = gid.y * numBlocksX + gid.x;
        quantizeGradientOfBlock(sumGradient, P, outputQ, avgIndex);
}
