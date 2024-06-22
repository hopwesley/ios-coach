#include <metal_stdlib>
using namespace metal;

constant float threshold = 1.29107;
constant int8_t sobelX[9] = {-1, 0, 1,
        -2, 0, 2,
        -1, 0, 1};

constant int8_t sobelY[9] = {-1, -2, -1,
        0,  0,  0,
        1,  2,  1};

// 内核函数1：灰度转换
kernel void toGrayFrame(
                        texture2d<float, access::read> inTexture [[texture(0)]],
                        device uchar* grayBuffer [[buffer(0)]],
                        constant uint &width [[buffer(1)]],
                        constant uint &height [[buffer(2)]],
                        uint2 gid [[thread_position_in_grid]])
{
        
        if (gid.x >= width || gid.y >= height) return;
        uint flippedY = height - 1 - gid.y;
        float4 color = inTexture.read(uint2(gid.x, flippedY));
        float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
        grayBuffer[gid.y * width + gid.x] = uchar(gray * 255.0);
}


// 内核函数2：空间梯度计算
kernel void spatialGradient(
                            device uchar* grayBuffer [[buffer(0)]],
                            device short* outGradientX [[buffer(1)]],
                            device short* outGradientY [[buffer(2)]],
                            constant uint &width [[buffer(3)]],
                            constant uint &height [[buffer(4)]],
                            uint2 gid [[thread_position_in_grid]])
{
        
        if (gid.x == 0 || gid.x >= width - 1 || gid.y == 0 || gid.y >= height - 1) return;
        short gradientX = 0, gradientY = 0;
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

// 内核函数3：时间梯度计算
kernel void timeGradient(
                         device uchar* grayBufferA [[buffer(0)]],
                         device uchar* grayBufferB [[buffer(1)]],
                         device uchar* outGradientT [[buffer(2)]],
                         constant uint &width [[buffer(3)]],
                         constant uint &height [[buffer(4)]],
                         uint2 gid [[thread_position_in_grid]])
{
        
        if (gid.x >= width || gid.y >= height) return;
        uint index = gid.y * width + gid.x;
        uchar diff = abs(grayBufferA[index] - grayBufferB[index]);
        outGradientT[index] = diff;
}


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
                                   device float *outputQ,
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
                outputQ[index * 10 + i] = (g_l2_norm * q_prime[i]) / q_prime_l2_len;
        }
}

// 内核函数4：量化处理
kernel void frameGradientByBlock(
                                 device short* gradientX [[buffer(0)]],
                                 device short* gradientY [[buffer(1)]],
                                 device uchar* gradientT [[buffer(2)]],
                                 device float* outputQ [[buffer(3)]],
                                 constant float3* P [[buffer(4)]],
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
        quantizeBlockHistogram(sumGradient, P, outputQ, avgIndex);
}
