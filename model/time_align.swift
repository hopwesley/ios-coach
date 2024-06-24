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

func histogramFromBlockForOneFrame(device: MTLDevice,
                                   commandQueue: MTLCommandQueue,
                                   rawImgA: MTLTexture,
                                   rawImgB: MTLTexture,
                                   width: Int,
                                   height: Int) -> MTLBuffer? {
        
        let blockSize = 4
        let library = device.makeDefaultLibrary()
        let gradient = library?.makeFunction(name: "spacetimeGradientExtraction")
        let gradientPipe = try! device.makeComputePipelineState(function: gradient!)
        
        let grayFunc = library?.makeFunction(name: "grayscaleKernelSingleChannel")
        let grayPipe = try! device.makeComputePipelineState(function: grayFunc!)
        
        let quantizedFunc = library?.makeFunction(name: "quantizeAvgerageGradientOfBlock")
        let quantizedPipe = try! device.makeComputePipelineState(function: quantizedFunc!)
        
        let size = width * height
        let numBlocksX = (width + blockSize - 1) / blockSize
        let numBlocksY = (height + blockSize - 1) / blockSize
        let numBlocks = numBlocksX * numBlocksY
        let PBufferSize = icosahedronCenterP.count * MemoryLayout<SIMD3<Float>>.stride
        var w = width
        var h = height
        var bSize = blockSize
        
        // Create buffer to store grayscale values
        guard let grayBufferCur = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
              let grayBufferPre = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
              let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared),
              let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared),
              let gradientTBuffer = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
              let avgGradientOneFrame = device.makeBuffer(length: numBlocks * 10 * MemoryLayout<Float>.stride, options: .storageModeShared),
              let PBuffer = device.makeBuffer(bytes: icosahedronCenterP, length: PBufferSize, options: .storageModeShared) else {
                
                print("Error: Failed to create metal buffer")
                return nil
        }
        
        memset(avgGradientOneFrame.contents(), 0, numBlocks * 10 * MemoryLayout<Float>.stride)
        memset(gradientXBuffer.contents(), 0, size * MemoryLayout<Int16>.stride)
        memset(gradientYBuffer.contents(), 0, size * MemoryLayout<Int16>.stride)
        
        // First command buffer for grayscale conversion
        var commandBuffer = commandQueue.makeCommandBuffer()!
        var computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(grayPipe)
        computeEncoder.setTexture(rawImgA, index: 0)
        computeEncoder.setBuffer(grayBufferPre, offset: 0, index: 0)
        var threadGroupSize = MTLSizeMake(8, 8, 1)
        var threadGroups = MTLSizeMake(
                (width + threadGroupSize.width - 1) / threadGroupSize.width,
                (height + threadGroupSize.height - 1) / threadGroupSize.height,
                1
        )
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Second command buffer for grayscale conversion
        commandBuffer = commandQueue.makeCommandBuffer()!
        computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(grayPipe)
        computeEncoder.setTexture(rawImgB, index: 0)
        computeEncoder.setBuffer(grayBufferCur, offset: 0, index: 0)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Third command buffer for gradient computation
        commandBuffer = commandQueue.makeCommandBuffer()!
        computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(gradientPipe)
        computeEncoder.setBuffer(grayBufferPre, offset: 0, index: 0)
        computeEncoder.setBuffer(grayBufferCur, offset: 0, index: 1)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(gradientTBuffer, offset: 0, index: 4)
        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Fourth command buffer for quantization
        commandBuffer = commandQueue.makeCommandBuffer()!
        computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.setComputePipelineState(quantizedPipe)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(gradientTBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(avgGradientOneFrame, offset: 0, index: 3)
        computeEncoder.setBuffer(PBuffer, offset: 0, index: 4)
        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
        computeEncoder.setBytes(&bSize, length: MemoryLayout<Int>.size, index: 7)
        threadGroupSize = MTLSize(width: DescriptorParam_M * DescriptorParam_m, height: DescriptorParam_M * DescriptorParam_m, depth: 1)
        threadGroups = MTLSize(
                width: (numBlocksX + threadGroupSize.width - 1) / threadGroupSize.width,
                height: (numBlocksY + threadGroupSize.height - 1) / threadGroupSize.height,
                depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        saveRawDataToFile(fileName: "gpu_grayBufferA.json", buffer: grayBufferCur, width: width, height: height, type: UInt8.self)
        saveRawDataToFile(fileName: "gpu_grayBufferB.json", buffer: grayBufferPre, width: width, height: height, type: UInt8.self)
        saveRawDataToFile(fileName: "gpu_gradientXBuffer.json", buffer: gradientXBuffer, width: width, height: height, type: Int16.self)
        saveRawDataToFile(fileName: "gpu_gradientYBuffer.json", buffer: gradientYBuffer, width: width, height: height, type: Int16.self)
        saveRawDataToFile(fileName: "gpu_gradientTBuffer.json", buffer: gradientTBuffer, width: width, height: height, type: UInt8.self)
        saveRawDataToFileWithDepth(fileName: "gpu_frame_quantity_\(blockSize).json", buffer: avgGradientOneFrame, width: numBlocksX, height: numBlocksY, depth: 10, type: Float.self)
        
        return nil
}

//
//
//func quantizeGradientOfBlockForOneFrame(device: MTLDevice,
//                                        commandQueue: MTLCommandQueue,
//                                        spaceTimeGradient: MTLComputePipelineState,
//                                        quantizeGradient: MTLComputePipelineState,
//                                        sumGradients:MTLComputePipelineState,
//                                        rawImgA:MTLTexture,
//                                        rawImgB:MTLTexture,
//                                        width: Int,
//                                        height: Int,
//                                        blockSize: Int) -> (MTLBuffer,MTLBuffer)? {
//
//        // Create a command buffer and a compute command encoder
//        var commandBuffer = commandQueue.makeCommandBuffer()!
//        var computeEncoder = commandBuffer.makeComputeCommandEncoder()!
//
//        let size = width * height
//        let numBlocksX = (width + blockSize - 1) / blockSize
//        let numBlocksY = (height + blockSize - 1) / blockSize
//        var numBlocks = numBlocksX * numBlocksY
//        let PBufferSize = icosahedronCenterP.count * MemoryLayout<SIMD3<Float>>.stride
//        var w = width
//        var h = height
//        var bSize = blockSize
//
//        // Create buffer to store grayscale values
//        guard let grayBufferCur = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
//              let grayBufferPre = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
//              let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared),
//              let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared),
//              let gradientTBuffer = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
//              let avgGradientOneFrame = device.makeBuffer(length: numBlocks * 10 * MemoryLayout<Float>.stride, options: .storageModeShared),
//              let finalGradient = device.makeBuffer(length: 10 * MemoryLayout<Float>.stride, options: .storageModeShared),
//              let PBuffer = device.makeBuffer(bytes: icosahedronCenterP, length: PBufferSize, options: .storageModeShared) else {
//
//                print("Error: Failed to create metal buffer")
//                return nil
//        }
//
//        memset(avgGradientOneFrame.contents(), 0, numBlocks * 10 * MemoryLayout<Float>.stride)
//        memset(gradientXBuffer.contents(), 0, size * MemoryLayout<Int16>.stride)
//        memset(gradientYBuffer.contents(), 0, size * MemoryLayout<Int16>.stride)
//
//        computeEncoder.setComputePipelineState(spaceTimeGradient)
//        computeEncoder.setTexture(rawImgA, index: 0)
//        computeEncoder.setTexture(rawImgB, index: 1)
//
//        computeEncoder.setBuffer(grayBufferPre, offset: 0, index: 0)
//        computeEncoder.setBuffer(grayBufferCur, offset: 0, index: 1)
//        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 2)
//        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 3)
//        computeEncoder.setBuffer(gradientTBuffer, offset: 0, index: 4)
//        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
//        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
//
//
//        var threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
//        var threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
//                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
//                                   depth: 1)
//        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
//        computeEncoder.endEncoding()
//
//        commandBuffer.commit()
//        commandBuffer.waitUntilCompleted()
//
//        // Fourth command buffer for quantization
//        commandBuffer = commandQueue.makeCommandBuffer()!
//        computeEncoder = commandBuffer.makeComputeCommandEncoder()!
//
//        computeEncoder.setComputePipelineState(quantizeGradient)
//        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 0)
//        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 1)
//        computeEncoder.setBuffer(gradientTBuffer, offset: 0, index: 2)
//        computeEncoder.setBuffer(avgGradientOneFrame, offset: 0, index: 3)
//        computeEncoder.setBuffer(PBuffer, offset: 0, index: 4)
//        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
//        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
//        computeEncoder.setBytes(&bSize, length: MemoryLayout<Int>.size, index: 7)
//
//        threadGroupSize = MTLSize(width: DescriptorParam_M * DescriptorParam_m,
//                                  height: DescriptorParam_M * DescriptorParam_m,
//                                  depth: 1)
//        threadGroups = MTLSize(
//                width: (numBlocksX + DescriptorParam_M * DescriptorParam_m - 1) / (DescriptorParam_M * DescriptorParam_m),
//                height: (numBlocksY + DescriptorParam_M * DescriptorParam_m - 1) / (DescriptorParam_M * DescriptorParam_m),
//                depth: 1
//        )
//        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
//        computeEncoder.endEncoding()
//
//        commandBuffer.commit()
//        commandBuffer.waitUntilCompleted()
//
//        // Fourth command buffer for quantization
//        commandBuffer = commandQueue.makeCommandBuffer()!
//        computeEncoder = commandBuffer.makeComputeCommandEncoder()!
//
//        memset(finalGradient.contents(), 0, 10 * MemoryLayout<Float>.stride)
//        computeEncoder.setComputePipelineState(sumGradients)
//        computeEncoder.setBuffer(avgGradientOneFrame, offset: 0, index: 0)
//        computeEncoder.setBuffer(finalGradient, offset: 0, index: 1)
//        computeEncoder.setBytes(&numBlocks, length: MemoryLayout<UInt>.size, index: 2)
//
//        threadGroupSize = MTLSize(width: 10, height: 1, depth: 1)
//        threadGroups = MTLSize(width: 1, height: 1, depth: 1)
//        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
//        computeEncoder.endEncoding()
//
//        commandBuffer.commit()
//        commandBuffer.waitUntilCompleted()
//
//        saveRawDataToFile(fileName: "gpu_grayBufferA.json", buffer: grayBufferCur, width: width, height: height, type: UInt8.self)
//        saveRawDataToFile(fileName: "gpu_grayBufferB.json", buffer: grayBufferPre, width: width, height: height, type: UInt8.self)
//        saveRawDataToFile(fileName: "gpu_gradientXBuffer.json", buffer: gradientXBuffer, width: width, height: height, type: Int16.self)
//        saveRawDataToFile(fileName: "gpu_gradientYBuffer.json", buffer: gradientYBuffer, width: width, height: height, type: Int16.self)
//        saveRawDataToFile(fileName: "gpu_gradientTBuffer.json", buffer: gradientTBuffer, width: width, height: height, type: UInt8.self)
//        saveRawDataToFileWithDepth(fileName: "gpu_frame_quantity_\(blockSize).json", buffer: avgGradientOneFrame,
//                                   width: numBlocksX, height: numBlocksY, depth: 10, type: Float.self)
//        saveRawDataToFile(fileName: "gpu_gradientSumOfOneFrame.json", buffer: finalGradient,  width: 10, height: 1,  type: Float.self)
//
//        return (avgGradientOneFrame, finalGradient)
//}

