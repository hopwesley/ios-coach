//
//  textureToBlockHistogram.metal
//  SportsCoach
//
//  Created by wesley on 2024/6/24.
//

#include <metal_stdlib>
using namespace metal;
constant float threshold = 1.29107;

constant int8_t sobelX[9] = {-1, 0, 1,
        -2, 0, 2,
        -1, 0, 1};

constant int8_t sobelY[9] = {-1, -2, -1,
        0,  0,  0,
        1,  2,  1};

constant float phi = 1.61803398875; // φ = (1 + sqrt(5)) / 2


kernel void  grayAndTimeDiff(texture2d<float, access::read> preTexture [[texture(0)]],
                             texture2d<float, access::read> texture [[texture(1)]],
                             device uchar* preGrayBuffer [[buffer(0)]],
                             device uchar* grayBuffer [[buffer(1)]],
                             device uchar* outGradientT [[buffer(2)]],
                             uint2 gid [[thread_position_in_grid]])
{
        uint width = texture.get_width();
        uint height = texture.get_height();
        if (gid.x >=  width|| gid.y >= height) {
                return;
        }
        
        
        uint flippedY = height - 1 - gid.y;
        
        float4 colorPre = preTexture.read(uint2(gid.x, flippedY));
        float4 color = texture.read(uint2(gid.x, flippedY));
        
        uchar grayUcharPre = uchar(dot(colorPre.rgb, float3(0.299, 0.587, 0.114)) * 255.0);
        uchar grayUchar = uchar(dot(color.rgb, float3(0.299, 0.587, 0.114)) * 255.0);
        
        uint index = gid.y * width + gid.x;
        preGrayBuffer[index] = grayUcharPre;
        grayBuffer[index] = grayUchar;
        outGradientT[index] = abs(preGrayBuffer[index] - grayBuffer[index]);
}

kernel void spaceGradient(
                          device uchar* grayBuffer [[buffer(0)]],
                          device short* outGradientX [[buffer(1)]],
                          device short* outGradientY [[buffer(2)]],
                          constant uint &width [[buffer(3)]],
                          constant uint &height [[buffer(4)]],
                          uint2 gid [[thread_position_in_grid]])
{
        if (gid.x == 0 || gid.x >= width - 1 || gid.y == 0 || gid.y >= height - 1) return;
        
        short gradientX = 0.0, gradientY = 0.0;
        
        int idx = 0;
        for (int j = -1; j <= 1; j++) {
                for (int i = -1; i <= 1; i++) {
                        uint index = (gid.y + j) * width + (gid.x + i);
                        float gray = short(grayBuffer[index]);
                        gradientX += gray * sobelX[idx];
                        gradientY += gray * sobelY[idx];
                        idx++;
                }
        }
        
        outGradientX[gid.y * width + gid.x] = gradientX;
        outGradientY[gid.y * width + gid.x] = gradientY;
}


inline float q_prime_l2_norm(float q_prime[10]) {
        float norm = 0.0;
        for (int i = 0; i < 10; ++i) {
                norm += q_prime[i] * q_prime[i];
        }
        return sqrt(norm);
}

inline void quantizeGradient(
                             float3 avgGradient,
                             constant float3 *normalizedP,
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
                float bin_i = dot(normalizedP[i], g_normalized);
                float bin_j = dot(normalizedP[i + 10], g_normalized);
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
                                            constant float3* normalizedP [[buffer(4)]],
                                            constant uint &width [[buffer(5)]],
                                            constant uint &height [[buffer(6)]],
                                            constant uint &blockSize [[buffer(7)]],
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
        
        quantizeGradient(sumGradient,normalizedP,avgGradientOneFrame, avgIndex);
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
