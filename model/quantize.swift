//
//  quantize.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/18.
//

import Foundation
import Metal
import simd



func quantizeGradients(device: MTLDevice, commandQueue: MTLCommandQueue,
                       pipelineState: MTLComputePipelineState,
                       grayBufferX: MTLBuffer, grayBufferY: MTLBuffer, grayBufferT: MTLBuffer,
                       width: Int, height: Int) -> MTLBuffer? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Failed to create command buffer.")
                return nil
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create compute encoder.")
                return nil
        }
        
        let size = width * height * 10
        
        guard let outputBuffer = device.makeBuffer(length: size * MemoryLayout<Float>.stride, options: .storageModeShared) else {
                print("Failed to create output buffer.")
                return nil
        }
        
        let PBufferSize = icosahedronCenterP.count * MemoryLayout<SIMD3<Float>>.stride
        guard let PBuffer = device.makeBuffer(bytes: icosahedronCenterP, length: PBufferSize, options: .storageModeShared) else {
                print("Failed to create P buffer.")
                return nil
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(grayBufferX, offset: 0, index: 0)
        computeEncoder.setBuffer(grayBufferY, offset: 0, index: 1)
        computeEncoder.setBuffer(grayBufferT, offset: 0, index: 2)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(PBuffer, offset: 0, index: 4)
        
        var w = width
        var h = height
        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let numThreadGroupsX = (width + threadGroupSize.width - 1) / threadGroupSize.width
        let numThreadGroupsY = (height + threadGroupSize.height - 1) / threadGroupSize.height
        let threadGroups = MTLSize(width: numThreadGroupsX, height: numThreadGroupsY, depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputBuffer
}

