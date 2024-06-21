//
//  time_align.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/21.
//

import MetalKit
import simd

func findBestAlingOffset(histoA:MTLBuffer, histoB:MTLBuffer)->(Int32,Int32)?{
        return nil
}
func videoCihper(url:URL,offset:Int32){
        
}


func quantizeFrameByBlockGradient(device: MTLDevice, commandQueue: MTLCommandQueue,
                                  pipelineState: MTLComputePipelineState,
                                  rawImgA:MTLTexture,rawImgB:MTLTexture,
                                  width: Int,  height: Int,
                                  blockSize: Int) -> MTLBuffer? {
        // Create a command buffer and a compute command encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create command buffer or compute encoder.")
                return nil
        }
        
        let size = width * height
        
        // Create buffer to store grayscale values
        guard let grayBufferA = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared) else {
                print("Error: Failed to create gray buffer")
                return nil
        }
        
        guard let grayBufferB = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared) else {
                print("Error: Failed to create gray buffer")
                return nil
        }
        let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared)!
        let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared)!
        
        guard let gradientTBuffer = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared) else {
                print("Failed to create output buffer.")
                return nil
        }
        
        let numBlocksX = (width + blockSize - 1) / blockSize
        let numBlocksY = (height + blockSize - 1) / blockSize
        let numBlocks = numBlocksX * numBlocksY
        // 将P数组传入到buffer
        guard let outputQBuffer = device.makeBuffer(length: numBlocks * 10 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
                print("Failed to create output buffer.")
                return nil
        }
        
        // 初始化outputQBuffer内容为0
        memset(outputQBuffer.contents(), 0, numBlocks * 10 * MemoryLayout<Float>.stride)
        let PBufferSize = icosahedronCenterP.count * MemoryLayout<SIMD3<Float>>.stride
        guard let PBuffer = device.makeBuffer(bytes: icosahedronCenterP, length: PBufferSize, options: .storageModeShared) else {
                print("Failed to create P buffer.")
                return nil
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(rawImgA, index: 0)
        computeEncoder.setTexture(rawImgB, index: 1)
        computeEncoder.setBuffer(grayBufferA, offset: 0, index: 0)
        computeEncoder.setBuffer(grayBufferB, offset: 0, index: 1)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(gradientTBuffer, offset: 0, index: 4)
        var w = width
        var h = height
        var bSize = blockSize
        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
        computeEncoder.setBuffer(PBuffer, offset: 0, index: 7)
        computeEncoder.setBytes(&bSize, length: MemoryLayout<Int>.size, index: 8)
        computeEncoder.setBuffer(outputQBuffer, offset: 0, index: 9)
        
        let threadGroupSize = MTLSize(width: DescriptorParam_M * DescriptorParam_m, height: DescriptorParam_M * DescriptorParam_m, depth: 1)
        let threadGroups = MTLSize(width: numBlocksX, height: numBlocksY, depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return nil
}
