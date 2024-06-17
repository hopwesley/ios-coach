#include <metal_stdlib>
using namespace metal;

//kernel void grayscaleKernel(texture2d<float, access::read> inTexture [[texture(0)]],
//                            texture2d<float, access::write> outTexture [[texture(1)]],
//                            uint2 gid [[thread_position_in_grid]]) {
//        if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) {
//                return;
//        }
//
//        // 计算反转的y坐标
//        uint flippedY = inTexture.get_height() - 1 - gid.y;
//
//        // 使用反转的坐标读取颜色
//        float4 color = inTexture.read(uint2(gid.x, flippedY));
//        float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
//        outTexture.write(float4(gray, gray, gray, color.a), gid);
//}


kernel void grayscaleKernelSingleChannel(texture2d<float, access::read> inTexture [[texture(0)]],
                                         device uchar* grayBuffer [[buffer(0)]],
                                         uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) {
                return;
        }
        
        // 计算反转的y坐标
        uint flippedY = inTexture.get_height() - 1 - gid.y;
        
        // 使用反转的坐标读取颜色
        float4 color = inTexture.read(uint2(gid.x, flippedY));
        float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
        uchar grayUchar = uchar(gray * 255.0);
        uint index = gid.y * inTexture.get_width() + gid.x;
        grayBuffer[index] = grayUchar;
}
