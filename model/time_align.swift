//
//  time_align.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/21.
//

import MetalKit
import simd
import Metal

func findBestAlignOffset(histoA: MTLBuffer, countA: Int, histoB: MTLBuffer, countB: Int,seqLen:Int) -> (Int32, Int32)? {
        
        let device = MTLCreateSystemDefaultDevice()!
        let commandQueue = device.makeCommandQueue()!
        let library = device.makeDefaultLibrary()!
        let function = library.makeFunction(name: "nccOfAllFrameByHistogram")!
        let nccPipelineState = try! device.makeComputePipelineState(function: function)
        
        let weightedNCCFunction = library.makeFunction(name: "calculateWeightedNCC")!
        let weightedNccPipeline = try! device.makeComputePipelineState(function: weightedNCCFunction)
        
        // Assumes that all buffers are of the same size
        var width = countB
        var height = countA
        
        var sequenceLength = min(width, height)
        if sequenceLength < seqLen{
                sequenceLength -= 1
        }else{
                sequenceLength = seqLen
        }
        
        var weightedWidth = width - sequenceLength + 1
        var weightedHeight = height - sequenceLength + 1
        
        let nccValuesCount = width * height
        let weightedNccValuesCount = weightedWidth * weightedHeight
        
        let nccValuesBuffer = device.makeBuffer(length: nccValuesCount * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        let weightedNccValuesBuffer = device.makeBuffer(length: weightedNccValuesCount * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        var encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(nccPipelineState)
        encoder.setBuffer(histoA, offset: 0, index: 0)
        encoder.setBuffer(histoB, offset: 0, index: 1)
        encoder.setBuffer(nccValuesBuffer, offset: 0, index: 2)
        
        encoder.setBytes(&width, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&height, length: MemoryLayout<UInt32>.size, index: 4)
        
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        var threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                   depth: 1)
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        print("new width no:\(weightedWidth) new height no:\(weightedHeight)")
        encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(weightedNccPipeline)
        encoder.setBuffer(nccValuesBuffer, offset: 0, index: 0)
        encoder.setBuffer(weightedNccValuesBuffer, offset: 0, index: 1)
        encoder.setBytes(&weightedWidth, length: MemoryLayout<UInt32>.size, index: 2)
        encoder.setBytes(&weightedHeight, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&sequenceLength, length: MemoryLayout<UInt32>.size, index: 4)
        encoder.setBytes(&width, length: MemoryLayout<UInt32>.size, index: 5)
        
        let threadWidth = (weightedWidth + threadGroupSize.width - 1) / threadGroupSize.width
        let threadHeight = (weightedHeight + threadGroupSize.height - 1) / threadGroupSize.height
        print("thread width:\(threadWidth) thread height:\(threadHeight)")
        
        threadGroups = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        guard  let (maxValue, maxIndex) = findMaxValueInBuffer(buffer: weightedNccValuesBuffer, count: weightedNccValuesCount)  else{
                return nil
        }
        
        saveRawDataToFile(fileName: "gpu_frame_histogram_A.json",
                          buffer: histoA, width: 10, height: countA, type: Float.self)
        saveRawDataToFile(fileName: "gpu_frame_histogram_B.json",
                          buffer: histoB, width: 10, height: countB, type: Float.self)
        saveRawDataToFile(fileName: "gpu_ncc_a_b.json", buffer: nccValuesBuffer, width:width , height: height, type: Float.self)
        
        
        saveRawDataToFile(fileName: "gpu_ncc_weighted_sum.json",
                          buffer: weightedNccValuesBuffer, width: weightedWidth, height: weightedHeight, type: Float.self)
        
        
        let aIdx = Int32(maxIndex / weightedWidth)
        let bIdx = Int32(maxIndex % weightedWidth)
        print("aIdx=\(aIdx) bIdx=\(bIdx) val=\(maxValue) maxIdx = \(maxIndex)")
        return (aIdx, bIdx)
}

func videoCihper(url:URL,offset:Int32){
        
}

func findMaxValueInBuffer(buffer: MTLBuffer, count: Int) -> (Float, Int)? {
        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: count)
        var maxValue: Float = -Float.greatestFiniteMagnitude
        var maxIndex: Int = -1
        
        for i in 0..<count {
                if pointer[i] > maxValue {
                        maxValue = pointer[i]
                        maxIndex = i
                }
        }
        
        if maxIndex == -1 {
                return nil
        } else {
                return (maxValue, maxIndex)
        }
}

