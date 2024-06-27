//
//  time_align.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/21.
//

import MetalKit
import simd
import Metal

func findBestAlignOffset(histoA: MTLBuffer, countA: Int, histoB: MTLBuffer, countB: Int,sequenceLength:Int) -> (Int32, Int32)? {
        let device = MTLCreateSystemDefaultDevice()!
        let commandQueue = device.makeCommandQueue()!
        let library = device.makeDefaultLibrary()!
        let function = library.makeFunction(name: "nccOfAllFrameByHistogram")!
        let pipelineState = try! device.makeComputePipelineState(function: function)
        
        let calculateWeightedNCCFunction = library.makeFunction(name: "calculateWeightedNCC")!
        let calculateWeightedNCCPipelineState = try! device.makeComputePipelineState(function: calculateWeightedNCCFunction)
        
        let findMaxNCCValueFunction = library.makeFunction(name: "findMaxNCCValue")!
        let findMaxNCCValuePipelineState = try! device.makeComputePipelineState(function: findMaxNCCValueFunction)
        
        
        // Assumes that all buffers are of the same size
        let width = countB
        let height = countA
        
        let nccValuesCount = countA * countB
        let nccValuesBuffer = device.makeBuffer(length: nccValuesCount * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        let newWidth = width - sequenceLength
        let newHeight = height - sequenceLength
        
        let weightedNccValuesBuffer = device.makeBuffer(length: newWidth * newHeight * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        var maxSum: Float = -Float.greatestFiniteMagnitude
        let maxSumBuffer = device.makeBuffer(bytes: &maxSum, length: MemoryLayout<Float>.size, options: .storageModeShared)!
        var maxI: Int32 = -1
        let maxIBuffer = device.makeBuffer(bytes: &maxI, length: MemoryLayout<Int32>.size, options: .storageModeShared)!
        var maxJ: Int32 = -1
        let maxJBuffer = device.makeBuffer(bytes: &maxJ, length: MemoryLayout<Int32>.size, options: .storageModeShared)!
        
        
        
        var widthVar = UInt32(width)
        var heightVar = UInt32(height)
        var sequenceLengthVar = UInt32(sequenceLength)
        var newWidthVar = UInt32(newWidth)
        var newHeightVar = UInt32(newHeight)
        
        let widthBuffer = device.makeBuffer(bytes: &widthVar, length: MemoryLayout<UInt32>.size, options: [])
        let heightBuffer = device.makeBuffer(bytes: &heightVar, length: MemoryLayout<UInt32>.size, options: [])
        let sequenceLengthBuffer = device.makeBuffer(bytes: &sequenceLengthVar, length: MemoryLayout<UInt32>.size, options: [])
        let newWidthBuffer = device.makeBuffer(bytes: &newWidthVar, length: MemoryLayout<UInt32>.size, options: [])
        let newHeightBuffer = device.makeBuffer(bytes: &newHeightVar, length: MemoryLayout<UInt32>.size, options: [])
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        var encoder = commandBuffer.makeComputeCommandEncoder()!
        
        encoder.setComputePipelineState(pipelineState)
        
        encoder.setBuffer(histoA, offset: 0, index: 0)
        encoder.setBuffer(histoB, offset: 0, index: 1)
        encoder.setBuffer(nccValuesBuffer, offset: 0, index: 2)
        encoder.setBuffer(widthBuffer, offset: 0, index: 3)
        encoder.setBuffer(heightBuffer, offset: 0, index: 4)
        
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                   depth: 1)
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        
        // Step 1: Calculate Weighted NCC Values
        encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(calculateWeightedNCCPipelineState)
        encoder.setBuffer(nccValuesBuffer, offset: 0, index: 0)
        encoder.setBuffer(weightedNccValuesBuffer, offset: 0, index: 1)
        encoder.setBuffer(widthBuffer, offset: 0, index: 2)
        encoder.setBuffer(heightBuffer, offset: 0, index: 3)
        encoder.setBuffer(sequenceLengthBuffer, offset: 0, index: 4)
        
        let threadGroupsNcc = MTLSize(width: (newWidth + threadGroupSize.width - 1) / threadGroupSize.width,
                                      height: (newHeight + threadGroupSize.height - 1) / threadGroupSize.height,
                                      depth: 1)
        encoder.dispatchThreadgroups(threadGroupsNcc, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        
        // Step 2: Find Max NCC Value
        encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(findMaxNCCValuePipelineState)
        encoder.setBuffer(weightedNccValuesBuffer, offset: 0, index: 0)
        encoder.setBuffer(maxSumBuffer, offset: 0, index: 1)
        encoder.setBuffer(maxIBuffer, offset: 0, index: 2)
        encoder.setBuffer(maxJBuffer, offset: 0, index: 3)
        encoder.setBuffer(newWidthBuffer, offset: 0, index: 4)
        encoder.setBuffer(newHeightBuffer, offset: 0, index: 5)
        
        let threadGroupsMax = MTLSize(width: (newWidth + threadGroupSize.width - 1) / threadGroupSize.width,
                                      height: (newHeight + threadGroupSize.height - 1) / threadGroupSize.height,
                                      depth: 1)
        encoder.dispatchThreadgroups(threadGroupsMax, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        saveRawDataToFile(fileName: "gpu_frame_histogram_A.json",
                          buffer: histoA, width: 10, height: countA, type: Float.self)
        saveRawDataToFile(fileName: "gpu_frame_histogram_B.json",
                          buffer: histoB, width: 10, height: countB, type: Float.self)
        saveRawDataToFile(fileName: "gpu_ncc_a_b.json", buffer: nccValuesBuffer, width: width, height: height, type: Float.self)
        return nil
}



func videoCihper(url:URL,offset:Int32){
        
}

func findMinMaxCoordinates(nccValues: [[Double]]) -> (gap: Int, error: Error?) {
        var minX = Int.max
        var minY = Int.max
        var maxX = Int.min
        var maxY = Int.min
        var found = false
        
        for i in 0..<nccValues.count {
                for j in 0..<nccValues[0].count {
                        if nccValues[i][j] != 0 {
                                if i < minX {
                                        minX = i
                                }
                                if j < minY {
                                        minY = j
                                }
                                if i > maxX {
                                        maxX = i
                                }
                                if j > maxY {
                                        maxY = j
                                }
                                found = true
                        }
                }
        }
        
        if !found {
                return (-1, NSError(domain: "NoNonZeroElements", code: 1, userInfo: [NSLocalizedDescriptionKey: "No non-zero elements found"]))
        }
        
        let gap = min(maxX - minX, maxY - minY)
        return (gap, nil)
}
