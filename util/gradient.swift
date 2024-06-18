//
//  gradient.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/18.
//

import Foundation
import Metal
import CoreVideo
import CoreImage

func timeGradient(device: MTLDevice, commandQueue: MTLCommandQueue,
                  pipelineState: MTLComputePipelineState,
                  grayFrameA: MTLBuffer, grayFrameB: MTLBuffer,
                  width: Int, height: Int) -> MTLBuffer? {
        let size = width * height
        
        // Create buffer for the output
        guard let outputBuffer = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared) else {
                print("Failed to create output buffer.")
                return nil
        }
        
        
        
        // Create a command buffer and a compute command encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create command buffer or compute encoder.")
                return nil
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(grayFrameA, offset: 0, index: 0)
        computeEncoder.setBuffer(grayFrameB, offset: 0, index: 1)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 2)
        var w = width
        var h = height
        computeEncoder.setBytes(&w, length: MemoryLayout<UInt>.size, index: 3)
        computeEncoder.setBytes(&h, length: MemoryLayout<UInt>.size, index: 4)
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                   depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputBuffer
}

func spatialGradient(device: MTLDevice, commandQueue: MTLCommandQueue,
                     pipelineState: MTLComputePipelineState,
                     grayBuffer: MTLBuffer, width: Int, height: Int) -> (MTLBuffer, MTLBuffer)? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Failed to create command buffer.")
                return nil
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create compute encoder.")
                return nil
        }
        
        let size = width * height
        
        let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared)!
        let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared)!
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(grayBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 2)
        var w = width
        var h = height
        computeEncoder.setBytes(&w, length: MemoryLayout<uint>.size, index: 3)
        computeEncoder.setBytes(&h, length: MemoryLayout<uint>.size, index: 4)
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                   depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return (gradientXBuffer, gradientYBuffer)
}

func convertToGrayscale(device: MTLDevice, commandQueue:MTLCommandQueue,
                        pipelineState:MTLComputePipelineState,
                        from videoFrame: CVPixelBuffer) -> MTLTexture? {
        // Create a texture descriptor for the input texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: CVPixelBufferGetWidth(videoFrame),
                height: CVPixelBufferGetHeight(videoFrame),
                mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        let inputTexture = device.makeTexture(descriptor: textureDescriptor)
        
        let ciImage = CIImage(cvPixelBuffer: videoFrame)
        let context = CIContext(mtlDevice: device)
        context.render(ciImage, to: inputTexture!, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Create an output texture
        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: inputTexture!.width,
                height: inputTexture!.height,
                mipmapped: false
        )
        outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)
        
        // Create a command buffer and a compute command encoder
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake(
                (inputTexture!.width + threadGroupSize.width - 1) / threadGroupSize.width,
                (inputTexture!.height + threadGroupSize.height - 1) / threadGroupSize.height,
                1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Get the grayscale image from the output texture
        return outputTexture
}
