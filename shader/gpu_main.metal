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
constant int HistogramSize = 10;
constant float MinNccVal = 0.95;

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


inline float q_prime_l2_norm(float q_prime[HistogramSize]) {
        float norm = 0.0;
        for (int i = 0; i < HistogramSize; ++i) {
                norm += q_prime[i] * q_prime[i];
        }
        return sqrt(norm);
}

inline void quantizeGradient(
                             float3 avgGradient,
                             constant float3 *normalizedP,
                             device float *qg,
                             uint index)
{
        // 计算 g 的 L2 范数并归一化
        float g_l2_norm = length(avgGradient);
        if (g_l2_norm == 0.0) {
                return;
        }
        float3 g_normalized = avgGradient / g_l2_norm;
        
        float q_prime[HistogramSize];  // 计算投影结果 q_i
        for (int i = 0; i < HistogramSize; ++i) {
                float bin_i = dot(normalizedP[i], g_normalized);
                float bin_j = dot(normalizedP[i + HistogramSize], g_normalized);
                q_prime[i] = fabs(bin_i) + fabs(bin_j) - threshold;
                q_prime[i] = max(q_prime[i], 0.0);
        }
        
        float q_prime_l2_len = q_prime_l2_norm(q_prime);
        if (q_prime_l2_len == 0.0) {
                return;
        }
        
        for (int i = 0; i < HistogramSize; ++i) {
                qg[index * HistogramSize + i] = (g_l2_norm * q_prime[i]) / q_prime_l2_len;
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
                                            constant uint &numBlocksX [[buffer(8)]],
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
        
        uint avgIndex = gid.y * numBlocksX + gid.x;
        quantizeGradient(sumGradient,normalizedP,avgGradientOneFrame, avgIndex);
}

kernel void sumQuantizedGradients(
                                  device float* avgGradientOneFrame [[buffer(0)]],
                                  device atomic_float* finalGradient [[buffer(1)]],
                                  constant uint &numBlocks [[buffer(2)]],
                                  constant uint &threadGroupSize [[buffer(3)]],
                                  uint gid [[thread_position_in_grid]],
                                  uint local_id [[thread_index_in_threadgroup]],
                                  threadgroup float* localSum)  // 使用 threadgroup 共享内存
{
        // 计算当前线程所属的维度
        uint dimension = gid / threadGroupSize;
        if (dimension >= HistogramSize) return; // 确保只处理前 10 个维度
        
        // 初始化局部累加结果
        float sum = 0.0;
        for (uint i = local_id; i < numBlocks; i += threadGroupSize) {
                uint index = i * HistogramSize + dimension;
                sum += avgGradientOneFrame[index];
        }
        
        localSum[local_id] = sum;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        
        // 并行归约过程
        for (uint offset = threadGroupSize / 2; offset > 0; offset >>= 1) { // 假设线程组大小为 32
                if (local_id < offset) {
                        localSum[local_id] += localSum[local_id + offset];
                }
                threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        
        if (local_id == 0) {
                atomic_fetch_add_explicit(&finalGradient[dimension], localSum[0], memory_order_relaxed);
        }
}

// 计算NCC值的函数
inline float calculateNCC(device float* histogramA, device float* histogramB) {
        float sumA = 0.0;
        float sumB = 0.0;
        float meanA = 0.0;
        float meanB = 0.0;
        float numerator = 0.0;
        float denominatorA = 0.0;
        float denominatorB = 0.0;
        
        for (uint i = 0; i < HistogramSize; i++) {
                sumA += histogramA[i];
                sumB += histogramB[i];
        }
        meanA = sumA / float(HistogramSize);
        meanB = sumB / float(HistogramSize);
        
        for (uint i = 0; i < HistogramSize; i++){
                float diffA = histogramA[i] - meanA;
                float diffB = histogramB[i] - meanB;
                numerator += diffA * diffB;
                denominatorA += diffA * diffA;
                denominatorB += diffB * diffB;
        }
        
        if (denominatorA == 0 || denominatorB == 0){
                return 0;
        }
        return numerator / (sqrt(denominatorA) * sqrt(denominatorB));
}


kernel void nccOfAllFrameByHistogram(device float* aHisGramFloat [[buffer(0)]],
                                     device float* bHisGramFloat [[buffer(1)]],
                                     device float* nccValues [[buffer(2)]],
                                     constant uint& width [[buffer(3)]],
                                     constant uint& height [[buffer(4)]],
                                     uint2 gid [[thread_position_in_grid]]) {
        uint i = gid.x;
        uint j = gid.y;
        
        if (i < width && j < height) {
                float ncc = calculateNCC(&aHisGramFloat[i * 10], &bHisGramFloat[j * 10]);
                if (ncc < MinNccVal){
                        nccValues[j * width + i] = 0;
                }else{
                        nccValues[j * width + i] = ncc;
                }
                
        }
}

kernel void calculateWeightedNCC(
                                 device float* nccValues [[buffer(0)]],
                                 device float* weightedNccValues [[buffer(1)]],
                                 constant uint& width [[buffer(2)]],
                                 constant uint& height [[buffer(3)]],
                                 constant uint& sequenceLength [[buffer(4)]],
                                 uint2 gid [[thread_position_in_grid]]
                                 )
{
        uint i = gid.x;
        uint j = gid.y;
        
        if (i <= width - sequenceLength && j <= height - sequenceLength) {
                float sum = 0.0;
                for (uint k = 0; k < sequenceLength; k++) {
                        sum += nccValues[(j + k) * width + (i + k)];
                }
                weightedNccValues[j * (width - sequenceLength) + i] = sum;
        }
}

inline void atomic_fetch_max(device atomic_float *object, float operand) {
        float current = atomic_load_explicit(object, memory_order_relaxed);
        while (current < operand && !atomic_compare_exchange_weak_explicit(object, &current, operand, memory_order_relaxed, memory_order_relaxed)) {
                // Loop until the value is successfully updated
        }
}
kernel void findMaxNCCValue(
                            device float* weightedNccValues [[buffer(0)]],
                            device atomic_float* maxSum [[buffer(1)]],
                            device atomic_int* maxI [[buffer(2)]],
                            device atomic_int* maxJ [[buffer(3)]],
                            constant uint& newWidth [[buffer(4)]],
                            constant uint& newHeight [[buffer(5)]],
                            uint2 gid [[thread_position_in_grid]]
                            )
{
        uint i = gid.x;
        uint j = gid.y;
        
        float value = weightedNccValues[j * newWidth + i];
        atomic_fetch_max(maxSum, value);
        if (atomic_load_explicit(maxSum, memory_order_relaxed) == value) {
                atomic_store_explicit(maxSum, value, memory_order_relaxed);
                atomic_store_explicit(maxI, int(i), memory_order_relaxed);
                atomic_store_explicit(maxJ, int(j), memory_order_relaxed);
        }
}
