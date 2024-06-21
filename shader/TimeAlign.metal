#include <metal_stdlib>
using namespace metal;

constant float threshold = 1.29107;

inline void toGrayFrame(texture2d<float, access::read> inTexture,
                        device uchar* grayBuffer,
                        uint2 gid,
                        uint width,
                        uint height)
{
        if (gid.x >= width || gid.y >= height) {
                return;
        }
        
        // 计算反转的y坐标
        uint flippedY = height - 1 - gid.y;
        
        // 使用反转的坐标读取颜色
        float4 color = inTexture.read(uint2(gid.x, flippedY));
        float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
        uchar grayUchar = uchar(gray * 255.0);
        uint index = gid.y * width + gid.x;
        grayBuffer[index] = grayUchar;
}

inline void spatialGradient(device uchar *grayBuffer,
                            device short *outGradientX,
                            device short *outGradientY,
                            uint width,
                            uint height,
                            uint2 gid)
{
        if (gid.x == 0 || gid.x >= width - 1 || gid.y == 0 || gid.y >= height - 1) return;
        
        // Sobel operator weights for X and Y directions
        int8_t sobelX[9] = {-1, 0, 1,
                -2, 0, 2,
                -1, 0, 1};
        
        int8_t sobelY[9] = {-1, -2, -1,
                0,  0,  0,
                1,  2,  1};
        
        short gradientX = 0;
        short gradientY = 0;
        
        // Compute gradients using the Sobel operator
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
        
        // Write the computed gradients to the output buffers as signed 16-bit integers
        outGradientX[gid.y * width + gid.x] = gradientX;
        outGradientY[gid.y * width + gid.x] = gradientY;
}

inline void timeGradient(device uchar *grayFrameA,
                         device uchar *grayFrameB,
                         device uchar *outputBuffer,
                         uint width,
                         uint height,
                         uint2 gid)
{
        if (gid.x >= width || gid.y >= height) {
                return;
        }
        
        uint index = gid.y * width + gid.x;
        uchar gray1 = grayFrameA[index];
        uchar gray2 = grayFrameB[index];
        
        uchar diff = abs(gray1 - gray2);
        
        outputBuffer[index] = diff;
}

inline float q_prime_l2_norm(float q_prime[10]) {
        float norm = 0.0;
        for (int i = 0; i < 10; ++i) {
                norm += q_prime[i] * q_prime[i];
        }
        return sqrt(norm);
}

inline void quantizeBlockHistogram(
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

inline void frameGradientByBlock(device const short *gradientX,
                                 device const short *gradientY,
                                 device const uchar *gradientT,
                                 device float *outputQ,
                                 constant float3 *P,
                                 uint width,
                                 uint height,
                                 uint blockSize,
                                 uint2 gid)
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
        
        if (count > 0) {
                sumGradient /= float(count);
        }
        
        // 调用量化梯度计算函数
        uint numBlocksX = (width + blockSize - 1) / blockSize;
        uint avgIndex = gid.y * numBlocksX + gid.x;
        quantizeBlockHistogram(sumGradient, P, outputQ, avgIndex);
}

kernel void frameQValByBlock(
                             texture2d<float, access::read> frameA [[texture(0)]],
                             texture2d<float, access::read> frameB [[texture(1)]],
                             device uchar* grayBufferA [[buffer(0)]],
                             device uchar* grayBufferB [[buffer(1)]],
                             device short *outGradientX [[buffer(2)]],
                             device short *outGradientY [[buffer(3)]],
                             device uchar *outGradientT [[buffer(4)]],
                             constant uint &width [[buffer(5)]],
                             constant uint &height [[buffer(6)]],
                             constant float3 *P [[buffer(7)]],
                             constant uint &blockSize [[buffer(8)]],
                             device float *outputQ [[buffer(9)]],
                             uint2 gid [[thread_position_in_grid]])
{
        toGrayFrame(frameA, grayBufferA, gid, width, height);
        toGrayFrame(frameB, grayBufferB, gid, width, height);
        
        spatialGradient(grayBufferB, outGradientX, outGradientY, width, height, gid);
        timeGradient(grayBufferB, grayBufferA, outGradientT, width, height, gid);
        
        frameGradientByBlock(outGradientX, outGradientY, outGradientT, outputQ, P, width, height, blockSize, gid);
}
