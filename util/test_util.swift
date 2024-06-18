//
//  test_util.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/18.
//

import Foundation
import Metal

func computeSpatialGradient(device: MTLDevice, commandQueue:MTLCommandQueue,
                            gradientPipelineState:MTLComputePipelineState,
                            for grayTexture: MTLTexture) -> ([Float], [Float])? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Failed to create command buffer.")
                return nil
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create compute encoder.")
                return nil
        }
        
        let width = grayTexture.width
        let height = grayTexture.height
        let size = width * height
        
        let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Float>.size, options: .storageModeShared)!
        let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        computeEncoder.setComputePipelineState(gradientPipelineState)
        computeEncoder.setTexture(grayTexture, index: 0)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 1)
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake(
                (width + threadGroupSize.width - 1) / threadGroupSize.width,
                (height + threadGroupSize.height - 1) / threadGroupSize.height,
                1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let gradientXPointer = gradientXBuffer.contents().bindMemory(to: Float.self, capacity: size)
        let gradientYPointer = gradientYBuffer.contents().bindMemory(to: Float.self, capacity: size)
        
        let gradientXArray = Array(UnsafeBufferPointer(start: gradientXPointer, count: size))
        let gradientYArray = Array(UnsafeBufferPointer(start: gradientYPointer, count: size))
        
        return (gradientXArray, gradientYArray)
}
