//
//  grayAndGradient.metal
//  SportsCoach
//
//  Created by wesley on 2024/7/4.
//

#include <metal_stdlib>
using namespace metal;

constant int HistogramSize = 10;
constant float MinNccVal = 0.9;

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
        
        uint aIdx = gid.y;
        uint bIdx = gid.x;
        if (gid.x >=  width|| gid.y >= height) {
                return;
        }
        
        float ncc = calculateNCC(&aHisGramFloat[aIdx * 10], &bHisGramFloat[bIdx * 10]);
        int index = aIdx*width+bIdx;
        if (ncc < MinNccVal){
                nccValues[index] = 0;
        }else{
                nccValues[index] = ncc;
        }
}


kernel void calculateWeightedNCC(
                                 device float* nccValues [[buffer(0)]],
                                 device float* weightedNccValues [[buffer(1)]],
                                 constant uint& width [[buffer(2)]],
                                 constant uint& height [[buffer(3)]],
                                 constant uint& sequenceLength [[buffer(4)]],
                                 constant uint& origWidth [[buffer(5)]],
                                 uint2 gid [[thread_position_in_grid]]
                                 )
{
        uint bIdx = gid.x;
        uint aIdx = gid.y;
        if (gid.x >=  width|| gid.y >= height) {
                return;
        }
        
        float sum = 0.0;
        for (uint k = 0; k < sequenceLength; k++) {
                uint index = (aIdx + k) * origWidth + (bIdx + k);
                sum += nccValues[index];
        }
        weightedNccValues[aIdx * width + bIdx] = sum;
}
