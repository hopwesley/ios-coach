#include <metal_stdlib>
using namespace metal;

constant float threshold = 1.29107;

inline float q_prime_l2_norm(float q_prime[10]) {
        float norm = 0.0;
        for (int i = 0; i < 10; ++i) {
                norm += q_prime[i] * q_prime[i];
        }
        return sqrt(norm);
}

inline void quantizeBlockHistogram(
                                   float3 avgGradient,
                                   constant float3 *P,
                                   device float *quantizeGradient,
                                   uint index)
{
        // 计算 g 的 L2 范数并归一化
        float g_l2_norm = length(avgGradient);
        if (g_l2_norm == 0.0) {
                return;
        }
        float3 g_normalized = avgGradient / g_l2_norm;
        
        float q_prime[10];  // 计算投影结果 q_i
        for (int i = 0; i < 10; ++i) {
                float bin_i = dot(P[i], g_normalized);
                float bin_j = dot(P[i + 10], g_normalized);
                q_prime[i] = fabs(bin_i) + fabs(bin_j) - threshold;
                q_prime[i] = max(q_prime[i], 0.0);
        }
        
        float q_prime_l2_len = q_prime_l2_norm(q_prime);
        if (q_prime_l2_len == 0.0) {
                return;
        }
        
        for (int i = 0; i < 10; ++i) {
                quantizeGradient[index * 10 + i] = (g_l2_norm * q_prime[i]) / q_prime_l2_len;
        }
}

kernel void quantizeAvgerageGradientOfBlock(
                                            device short* gradientX [[buffer(0)]],
                                            device short* gradientY [[buffer(1)]],
                                            device uchar* gradientT [[buffer(2)]],
                                            device float* avgGradientOneFrame [[buffer(3)]],
                                            constant float3* P [[buffer(4)]],
                                            constant uint &width [[buffer(5)]],
                                            constant uint &height [[buffer(6)]],
                                            constant uint &blockSize [[buffer(7)]],
                                            device float* gradientOfFrame [[buffer(8)]],
                                            uint2 gid [[thread_position_in_grid]])
{
        uint blockStartX = gid.x * blockSize;
        uint blockStartY = gid.y * blockSize;
        if (blockStartX >= width || blockStartY >= height) return;
        float3 sumGradient = float3(0.0, 0.0, 0.0);
        int count = 0;
        for (uint y = blockStartY; y < blockStartY + blockSize && y < height; ++y) {
                for (uint x = blockStartX; x < blockStartX + blockSize && x < width; ++x) {
                        uint index = y * width + x;
                        sumGradient += float3(float(gradientX[index]), float(gradientY[index]), float(gradientT[index]));
                        count++;
                }
        }
        if (count > 0) sumGradient /= float(count);
        uint numBlocksX = (width + blockSize - 1) / blockSize;
        uint avgIndex = gid.y * numBlocksX + gid.x;
        quantizeBlockHistogram(sumGradient, P, avgGradientOneFrame, avgIndex);
}


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
