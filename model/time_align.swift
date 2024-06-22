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
        let numBlocksX = (width + blockSize - 1) / blockSize
        let numBlocksY = (height + blockSize - 1) / blockSize
        let numBlocks = numBlocksX * numBlocksY
        let PBufferSize = icosahedronCenterP.count * MemoryLayout<SIMD3<Float>>.stride
        var w = width
        var h = height
        var bSize = blockSize
        
        // Create buffer to store grayscale values
        guard let grayBufferA = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
              let grayBufferB = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
              let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared),
              let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared),
              let gradientTBuffer = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared),
              let outputQBuffer = device.makeBuffer(length: numBlocks * 10 * MemoryLayout<Float>.stride, options: .storageModeShared),
              let PBuffer = device.makeBuffer(bytes: icosahedronCenterP, length: PBufferSize, options: .storageModeShared) else {
                
                print("Error: Failed to create metal buffer")
                return nil
        }
        
        memset(outputQBuffer.contents(), 0, numBlocks * 10 * MemoryLayout<Float>.stride)
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(rawImgA, index: 0)
        computeEncoder.setTexture(rawImgB, index: 1)
        computeEncoder.setBuffer(grayBufferA, offset: 0, index: 0)
        computeEncoder.setBuffer(grayBufferB, offset: 0, index: 1)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(gradientTBuffer, offset: 0, index: 4)
        computeEncoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
        computeEncoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
        computeEncoder.setBuffer(PBuffer, offset: 0, index: 7)
        computeEncoder.setBytes(&bSize, length: MemoryLayout<Int>.size, index: 8)
        computeEncoder.setBuffer(outputQBuffer, offset: 0, index: 9)
        
        let threadGroupSize = MTLSize(width: DescriptorParam_M * DescriptorParam_m, height: DescriptorParam_M * DescriptorParam_m, depth: 1)
        let threadGroups = MTLSize(
                width: (numBlocksX + DescriptorParam_M * DescriptorParam_m - 1) / (DescriptorParam_M * DescriptorParam_m),
                height: (numBlocksY + DescriptorParam_M * DescriptorParam_m - 1) / (DescriptorParam_M * DescriptorParam_m),
                depth: 1
        )
        
        print("numBlocksX=(\(numBlocksX)),numBlocksY=(\(numBlocksY)),width=(\(threadGroups.width),height=(\(threadGroups.height))")
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        saveRawDataToFile(fileName: "grayBufferA.json",
                          buffer: grayBufferA,
                          width: w,
                          height: h,
                          type: UInt8.self)
        
        saveRawDataToFile(fileName: "grayBufferB.json",
                          buffer: grayBufferB,
                          width: w,
                          height: h,
                          type: UInt8.self)
        
        saveRawDataToFile(fileName: "gradientXBuffer.json",
                          buffer: gradientXBuffer,
                          width: w,
                          height: h,
                          type: Int16.self)
        
        saveRawDataToFile(fileName: "gradientYBuffer.json",
                          buffer: gradientYBuffer,
                          width: w,
                          height: h,
                          type: Int16.self)
        
        saveRawDataToFile(fileName: "gradientTBuffer.json",
                          buffer: gradientTBuffer,
                          width: w,
                          height: h,
                          type: UInt8.self)
        
        saveRawDataToFileWithDepth(fileName: "gpu_frame_quantity_\(blockSize).json",
                                   buffer: outputQBuffer,
                                   width: numBlocksX,
                                   height: numBlocksY,
                                   depth: 10,
                                   type: Float.self)
        return outputQBuffer
}
