//
//  block_quantize.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/19.
//

import Foundation
import Metal

let DescriptorParam_M = 2
let DescriptorParam_m = 4

func blockAvgGradientQuantize(device: MTLDevice, commandQueue: MTLCommandQueue,
                               pipelineState: MTLComputePipelineState,
                               gradientX: MTLBuffer, gradientY: MTLBuffer, gradientT: MTLBuffer,
                               width: Int, height: Int, blockSize: Int) -> MTLBuffer? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Failed to create command buffer.")
                return nil
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create compute encoder.")
                return nil
        }
        
        let numBlocksX = (width + blockSize - 1) / blockSize
        let numBlocksY = (height + blockSize - 1) / blockSize
        let numBlocks = numBlocksX * numBlocksY
        
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
        computeEncoder.setBuffer(gradientX, offset: 0, index: 0)
        computeEncoder.setBuffer(gradientY, offset: 0, index: 1)
        computeEncoder.setBuffer(gradientT, offset: 0, index: 2)
        computeEncoder.setBuffer(outputQBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(PBuffer, offset: 0, index: 4)
        
        var w = width
        var h = height
        var bSize = blockSize
        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
        computeEncoder.setBytes(&bSize, length: MemoryLayout<Int>.size, index: 7)
        
        let threadGroupSize = MTLSize(width: DescriptorParam_M * DescriptorParam_m, height: DescriptorParam_M * DescriptorParam_m, depth: 1)
        let threadGroups = MTLSize(width: numBlocksX, height: numBlocksY, depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputQBuffer
}
