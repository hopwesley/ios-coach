//
//  compare.metal
//  SportsCoach
//
//  Created by wesley on 2024/7/5.
//

#include <metal_stdlib>
using namespace metal;

constant int Cell_M = 2;
constant int Cell_m = 4;

constant float threshold = 1.29107;

constant int8_t sobelX[9] = {-1, 0, 1,
        -2, 0, 2,
        -1, 0, 1};

constant int8_t sobelY[9] = {-1, -2, -1,
        0,  0,  0,
        1,  2,  1};

constant int blockNumOneDescriptor = Cell_M * Cell_m;

constant float weightsWithDistance[3][blockNumOneDescriptor][blockNumOneDescriptor] = {
        {
        {0.00988869936854563, 0.01192804830576989, 0.013516249485789531, 0.014387972682974322, 0.014387972682974322, 0.013516249485789531, 0.01192804830576989, 0.00988869936854563},
        {0.01192804830576989, 0.014387972682974322, 0.016303708988480107, 0.017355207878046373, 0.017355207878046373, 0.016303708988480107, 0.014387972682974322, 0.01192804830576989},
        {0.013516249485789531, 0.016303708988480107, 0.018474522619547944, 0.019666026959661444, 0.019666026959661444, 0.018474522619547944, 0.016303708988480107, 0.013516249485789531},
        {0.014387972682974322, 0.017355207878046373, 0.019666026959661444, 0.020934376727488848, 0.020934376727488848, 0.019666026959661444, 0.017355207878046373, 0.014387972682974322},
        {0.014387972682974322, 0.017355207878046373, 0.019666026959661444, 0.020934376727488848, 0.020934376727488848, 0.019666026959661444, 0.017355207878046373, 0.014387972682974322},
        {0.013516249485789531, 0.016303708988480107, 0.018474522619547944, 0.019666026959661444, 0.019666026959661444, 0.018474522619547944, 0.016303708988480107, 0.013516249485789531},
        {0.01192804830576989, 0.014387972682974322, 0.016303708988480107, 0.017355207878046373, 0.017355207878046373, 0.016303708988480107, 0.014387972682974322, 0.01192804830576989},
        {0.00988869936854563, 0.01192804830576989, 0.013516249485789531, 0.014387972682974322, 0.014387972682974322, 0.013516249485789531, 0.01192804830576989, 0.00988869936854563}
        },
        {
        {0.002033071871452886, 0.004304013185640522, 0.007096118088539348, 0.009111595985502156, 0.009111595985502156, 0.007096118088539348, 0.004304013185640522, 0.002033071871452886},
        {0.004304013185640522, 0.009111595985502156, 0.0150224821113233, 0.019289248852676043, 0.019289248852676043, 0.0150224821113233, 0.009111595985502156, 0.004304013185640522},
        {0.007096118088539348, 0.0150224821113233, 0.024767885795650896, 0.031802594879235035, 0.031802594879235035, 0.024767885795650896, 0.0150224821113233, 0.007096118088539348},
        {0.009111595985502156, 0.019289248852676043, 0.031802594879235035, 0.0408353401415612, 0.0408353401415612, 0.031802594879235035, 0.019289248852676043, 0.009111595985502156},
        {0.009111595985502156, 0.019289248852676043, 0.031802594879235035, 0.0408353401415612, 0.0408353401415612, 0.031802594879235035, 0.019289248852676043, 0.009111595985502156},
        {0.007096118088539348, 0.0150224821113233, 0.024767885795650896, 0.031802594879235035, 0.031802594879235035, 0.024767885795650896, 0.0150224821113233, 0.007096118088539348},
        {0.004304013185640522, 0.009111595985502156, 0.0150224821113233, 0.019289248852676043, 0.019289248852676043, 0.0150224821113233, 0.009111595985502156, 0.004304013185640522},
        {0.002033071871452886, 0.004304013185640522, 0.007096118088539348, 0.009111595985502156, 0.009111595985502156, 0.007096118088539348, 0.004304013185640522, 0.002033071871452886}
        },
        {
        {7.616241169186581e-7, 0.00001529762932195991, 0.00011303504124060822, 0.0003072610985834641, 0.0003072610985834641, 0.00011303504124060822, 0.00001529762932195991, 7.616241169186581e-7},
        {0.00001529762932195991, 0.0003072610985834641, 0.0022703694944522772, 0.006171504140657374, 0.006171504140657374, 0.0022703694944522772, 0.0003072610985834641, 0.00001529762932195991},
        {0.00011303504124060822, 0.0022703694944522772, 0.016775887559808696, 0.04560159031010013, 0.04560159031010013, 0.016775887559808696, 0.0022703694944522772, 0.00011303504124060822},
        {0.0003072610985834641, 0.006171504140657374, 0.04560159031010013, 0.12395797428877928, 0.12395797428877928, 0.04560159031010013, 0.006171504140657374, 0.0003072610985834641},
        {0.0003072610985834641, 0.006171504140657374, 0.04560159031010013, 0.12395797428877928, 0.12395797428877928, 0.04560159031010013, 0.006171504140657374, 0.0003072610985834641},
        {0.00011303504124060822, 0.0022703694944522772, 0.016775887559808696, 0.04560159031010013, 0.04560159031010013, 0.016775887559808696, 0.0022703694944522772, 0.00011303504124060822},
        {0.00001529762932195991, 0.0003072610985834641, 0.0022703694944522772, 0.006171504140657374, 0.006171504140657374, 0.0022703694944522772, 0.0003072610985834641, 0.00001529762932195991},
        {7.616241169186581e-7, 0.00001529762932195991, 0.00011303504124060822, 0.0003072610985834641, 0.0003072610985834641, 0.00011303504124060822, 0.00001529762932195991, 7.616241169186581e-7}
        }
};


constant int HistogramSize = 10;

inline void  grayAndTimeDiff(texture2d<float, access::read> preTexture ,
                             texture2d<float, access::read> texture ,
                             device uchar* preGrayBuffer ,
                             device uchar* grayBuffer ,
                             device uchar* outGradientT ,
                             const uint width,
                             const uint height,
                             uint2 gid )
{
        
        
        
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


kernel void  grayAndTimeDiffTwoFrame(texture2d<float, access::read> preTexture [[texture(0)]],
                                     texture2d<float, access::read> texture [[texture(1)]],
                                     texture2d<float, access::read> preTextureB [[texture(2)]],
                                     texture2d<float, access::read> textureB [[texture(3)]],
                                     device uchar* preGrayBuffer [[buffer(0)]],
                                     device uchar* grayBuffer [[buffer(1)]],
                                     device uchar* outGradientT [[buffer(2)]],
                                     device uchar* preGrayBufferB [[buffer(3)]],
                                     device uchar* grayBufferB [[buffer(4)]],
                                     device uchar* outGradientTB [[buffer(5)]],
                                     uint2 gid [[thread_position_in_grid]])
{
        uint width = texture.get_width();
        uint height = texture.get_height();
        if (gid.x >=  width|| gid.y >= height) {
                return;
        }
        grayAndTimeDiff(preTexture,texture,preGrayBuffer,grayBuffer,outGradientT,width, height,gid);
        grayAndTimeDiff(preTextureB,textureB,preGrayBufferB,grayBufferB,outGradientTB,width, height,gid);
}




inline void spaceGradient(device uchar* grayBuffer,
                          device short* outGradientX,
                          device short* outGradientY,
                          constant uint &width,
                          constant uint &height,
                          uint2 gid)
{
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


kernel void spaceGradientTwoFrameTwoFrame(
                                          device uchar* grayBuffer [[buffer(0)]],
                                          device short* outGradientX [[buffer(1)]],
                                          device short* outGradientY [[buffer(2)]],
                                          device uchar* grayBufferB [[buffer(3)]],
                                          device short* outGradientXB [[buffer(4)]],
                                          device short* outGradientYB [[buffer(5)]],
                                          constant uint &width [[buffer(6)]],
                                          constant uint &height [[buffer(7)]],
                                          uint2 gid [[thread_position_in_grid]])
{
        if (gid.x == 0 || gid.x >= width - 1 || gid.y == 0 || gid.y >= height - 1) return;
        
        spaceGradient(grayBuffer,outGradientX,outGradientY,width, height, gid);
        
        spaceGradient(grayBufferB,outGradientXB,outGradientYB,width, height, gid);
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

inline void avgBlockGradient(
                             device short* gradientX,
                             device short* gradientY,
                             device uchar* gradientT,
                             device float* avgGradientOneFrame,
                             constant float3* normalizedP,
                             constant uint &width ,
                             constant uint &height ,
                             constant uint &blockSize,
                             constant uint &numBlocksX,
                             uint2 gid )
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
        quantizeGradient(sumGradient, normalizedP, avgGradientOneFrame, avgIndex);
}

kernel void quantizeAvgerageGradientOfTwoBlock(
                                               device short* gradientX [[buffer(0)]],
                                               device short* gradientY [[buffer(1)]],
                                               device uchar* gradientT [[buffer(2)]],
                                               device float* avgGradientOneFrame [[buffer(3)]],
                                               device short* gradientXB [[buffer(4)]],
                                               device short* gradientYB [[buffer(5)]],
                                               device uchar* gradientTB [[buffer(6)]],
                                               device float* avgGradientOneFrameB [[buffer(7)]],
                                               constant float3* normalizedP [[buffer(8)]],
                                               constant uint &width [[buffer(9)]],
                                               constant uint &height [[buffer(10)]],
                                               constant uint &blockSize [[buffer(11)]],
                                               constant uint &numBlocksX [[buffer(12)]],
                                               uint2 gid [[thread_position_in_grid]])
{
        
        avgBlockGradient(gradientX,gradientY,gradientT,avgGradientOneFrame,normalizedP,width, height,blockSize,numBlocksX,gid);
        
        avgBlockGradient(gradientXB,gradientYB,gradientTB,avgGradientOneFrameB,normalizedP,width, height,blockSize,numBlocksX,gid);
}
