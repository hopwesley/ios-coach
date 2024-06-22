//
//  common_gradient.metal
//  SportsCoach
//
//  Created by wesley on 2024/6/22.
//

#include <metal_stdlib>
using namespace metal;


constant int8_t sobelX[9] = {-1, 0, 1,
        -2, 0, 2,
        -1, 0, 1};

constant int8_t sobelY[9] = {-1, -2, -1,
        0,  0,  0,
        1,  2,  1};

inline void toGrayFrame(texture2d<float, access::read> inTexture,
                        device uchar* grayBuffer,
                        uint2 gid,
                        uint width,
                        uint height)
{
        
        if (gid.x >= width || gid.y >= height) return;
        uint flippedY = height - 1 - gid.y;
        float4 color = inTexture.read(uint2(gid.x, flippedY));
        float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
        grayBuffer[gid.y * width + gid.x] = uchar(gray * 255.0);
}

inline void spatialGradient(device uchar *grayBufferCur,
                            device uchar *grayBufferPre,
                            device short *outGradientX,
                            device short *outGradientY,
                            device uchar *outGradientT,
                            uint width,
                            uint height,
                            uint2 gid)
{
        
        if (gid.x == 0 || gid.x >= width - 1 || gid.y == 0 || gid.y >= height - 1) return;
        short gradientX = 0, gradientY = 0;
        int idx = 0;
        for (int j = -1; j <= 1; j++) {
                for (int i = -1; i <= 1; i++) {
                        uint index = (gid.y + j) * width + (gid.x + i);
                        float gray = short(grayBufferCur[index]);
                        gradientX += gray * sobelX[idx];
                        gradientY += gray * sobelY[idx];
                        idx++;
                }
        }
        
        uint index = gid.y * width + gid.x;
        uchar diff = abs(grayBufferCur[index] - grayBufferPre[index]);
        outGradientT[index] = diff;
        outGradientX[gid.y * width + gid.x] = gradientX;
        outGradientY[gid.y * width + gid.x] = gradientY;
}

kernel void spacetimeGradientExtraction(
                                        texture2d<float, access::read> framePrevious [[texture(0)]],
                                        texture2d<float, access::read> frameCurrent [[texture(1)]],
                                        device uchar* grayBufferPre [[buffer(0)]],
                                        device uchar* grayBufferCur [[buffer(1)]],
                                        device short* outGradientX [[buffer(2)]],
                                        device short* outGradientY [[buffer(3)]],
                                        device uchar* outGradientT [[buffer(4)]],
                                        constant uint &width [[buffer(5)]],
                                        constant uint &height [[buffer(6)]],
                                        uint2 gid [[thread_position_in_grid]])
{
        toGrayFrame(framePrevious, grayBufferPre, gid, width, height);
        toGrayFrame(frameCurrent, grayBufferCur, gid, width, height);
        spatialGradient(grayBufferCur,grayBufferPre,outGradientX,outGradientY,outGradientT,width,height,gid);
}
