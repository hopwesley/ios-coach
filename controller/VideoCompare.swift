//
//  VideoCompare.swift
//  SportsCoach
//
//  Created by wesley on 2024/7/4.
//
import Foundation

import AVFoundation
import CoreImage

class VideoCompare: ObservableObject {
        @Published var processingMessage: String = "开始处理..."
        
        var videoWidth:Int = 0
        var videoHeight:Int = 0
        var pixelSize:Int = 0
        var numBlocksX:[Int] = [0,0,0]
        var numBlockNo:[Int] = [0,0,0]
        var numBlocksY:[Int] = [0,0,0]
        var blockSizeInPixel:[Int] = [0,0,0]
        var descriptorNumY:[Int] = [0,0,0]
        var descriptorNumX:[Int] = [0,0,0]
        var descriptorNo:[Int] = [0,0,0]
        
        var textureDescriptor:MTLTextureDescriptor!
        var assetA:AVAsset!
        var assetB:AVAsset!
        
        var device:MTLDevice!
        var commandQueue: MTLCommandQueue!
        
        var grayAndDiffPipe: MTLComputePipelineState!
        var spaceGradientPipe: MTLComputePipelineState!
        var averageBlockGradientPipe: MTLComputePipelineState!
        var wtlPipe: MTLComputePipelineState!
        var biLinearPipe: MTLComputePipelineState!
        var normlizePipe:MTLComputePipelineState!
        var maxMinPipe:MTLComputePipelineState!
        var percentileHistogramPipe:MTLComputePipelineState!
        var percentilePipe:MTLComputePipelineState!
        
        var grayBufferPreB:MTLBuffer?
        var grayBufferCurB:MTLBuffer?
        var gradientBufferXB:MTLBuffer?
        var gradientBufferYB:MTLBuffer?
        var gradientBufferTB:MTLBuffer?
        var avgGradientOfBlockB:[MTLBuffer?]=[]
        
        var gradientMagnitude:MTLBuffer?
#if TmpDescData
        var descriptorPipe: MTLComputePipelineState!
        var descriptorBufferB:[MTLBuffer?]=[]
        var descriptorBufferA:[MTLBuffer?]=[]
#endif
        
        var grayBufferPreA:MTLBuffer?
        var grayBufferCurA:MTLBuffer?
        var gradientBufferXA:MTLBuffer?
        var gradientBufferYA:MTLBuffer?
        var gradientBufferTA:MTLBuffer?
        var avgGradientOfBlockA:[MTLBuffer?]=[]
        
        var fullWtlBuffer:[MTLBuffer?]=[]
        var fullWtlInOneBuffer:MTLBuffer?
        var wtlOfAllLevel:[MTLBuffer?]=[]
        var finalImgBuffer:MTLBuffer?
        var projectionBuf:MTLBuffer?
        
        var pixelThreadGrpNo:MTLSize?
        var pixelThreadGrpSize:MTLSize = MTLSize(width: PixelThreadWidth,
                                                 height: PixelThreadHeight,
                                                 depth: 1)
        var blockThreadGrpSize:[MTLSize?]=[]
        var blockThreadGrpNo:[MTLSize?]=[]
        var descriptorThreadGrpSize:MTLSize = MTLSize(width: 8,
                                                      height: 8,
                                                      depth: 1)
        var descriptorThreadGrpNo:[MTLSize?]=[]
        
        let threadsPerGroupMaxMin = MTLSize(width: threadGroupSizeForMaxMin, height: 1, depth: 1)
        var numGroupsMaxMin:MTLSize?
        var percentileBuffer:MTLBuffer?
        var numGrpPercentile:MTLSize?
        var maxMinBuffer:MTLBuffer?
        var percentileLowHighBuffer:MTLBuffer?
        
        func CompareAction(videoA:URL,videoB:URL)async throws{
                self.assetA = AVAsset(url: videoA)
                self.assetB = AVAsset(url: videoB)
                
                logProcessInfo("初始化GPU")
                try initGpuDevice()
                try await self.prepareVideoParam()
                try await  self.processVideo()
        }
        
        func initGpuDevice() throws{
                guard let d =  MTLCreateSystemDefaultDevice() else{
                        throw ASError.gpuBufferErr
                }
                self.device = d
                guard let queue  = device.makeCommandQueue() else{
                        throw ASError.gpuBufferErr
                }
                self.commandQueue = queue
                guard let library = device.makeDefaultLibrary() else{
                        throw ASError.gpuDeviceErr
                }
                
                guard let grayAndDiff = library.makeFunction(name: "grayAndTimeDiffTwoFrame"),
                      let spaceGradientFun = library.makeFunction(name: "spaceGradientTwoFrameTwoFrame"),
                      let quantizeGradientFun = library.makeFunction(name: "quantizeAvgerageGradientOfTwoBlock"),
                      let descriptorFun = library.makeFunction(name: "normalizedDescriptor"),
                      let wtlFun = library.makeFunction(name: "wtlBetweenTwoFrame"),
                      let bilinearFun = library.makeFunction(name: "applyBiLinearInterpolationToFullFrame"),
                      let normlizeFun  =  library.makeFunction(name: "normalizeImageFromWtl"),
                      let minMaxFun  =  library.makeFunction(name: "reduceMinMaxKernel"),
                      let ptHistoFun  =  library.makeFunction(name: "calculateHistogram"),
                      let percentileFun  =  library.makeFunction(name: "calculatePercentiles") else{
                        throw ASError.shaderLoadErr
                }
                
                grayAndDiffPipe = try device.makeComputePipelineState(function: grayAndDiff)
                spaceGradientPipe = try device.makeComputePipelineState(function: spaceGradientFun)
                averageBlockGradientPipe = try device.makeComputePipelineState(function: quantizeGradientFun)
                wtlPipe = try device.makeComputePipelineState(function: wtlFun)
                biLinearPipe = try device.makeComputePipelineState(function: bilinearFun)
                normlizePipe = try device.makeComputePipelineState(function: normlizeFun)
                maxMinPipe =  try device.makeComputePipelineState(function: minMaxFun)
                percentilePipe =  try device.makeComputePipelineState(function: percentileFun)
                percentileHistogramPipe  =  try device.makeComputePipelineState(function: ptHistoFun)
                
                avgGradientOfBlockA = Array(repeating: nil, count: 3)
                avgGradientOfBlockB = Array(repeating: nil, count: 3)
                descriptorThreadGrpNo = Array(repeating: nil, count: 3)
                blockThreadGrpNo = Array(repeating: nil, count: 3)
                blockThreadGrpSize = Array(repeating: nil, count: 3)
                wtlOfAllLevel = Array(repeating: nil, count: 3)
                fullWtlBuffer = Array(repeating: nil, count: 3)
#if TmpDescData
                descriptorPipe = try device.makeComputePipelineState(function: descriptorFun)
                descriptorBufferA = Array(repeating: nil, count: 3)
                descriptorBufferB = Array(repeating: nil, count: 3)
#endif
        }
        
        private func prepareVideoParam() async throws{
                guard let videoTrack = try await self.assetA.loadTracks(withMediaType: .video).first else {
                        throw ASError.noValidVideoTrack
                }
                
                let videoSize = try await videoTrack.load(.naturalSize)
                self.videoWidth = Int(videoSize.width)
                self.videoHeight = Int(videoSize.height)
                self.pixelSize = self.videoWidth * self.videoHeight
                
                self.textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: self.videoWidth,
                        height: self.videoHeight,
                        mipmapped: false
                )
                textureDescriptor.usage = [.shaderRead, .shaderWrite]
                
        }
        
        private func prepareFrameBuffer() throws{
                
                guard let bufferPreA = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferA = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferTA = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferXA = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared),
                      let bufferYA = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared),
                      let bufferPreB = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferB = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferTB = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferXB = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared),
                      let bufferYB = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared),
                      let pBuffer = device.makeBuffer(bytes: normalizedP, length: MemoryLayout<SIMD3<Float>>.stride * normalizedP.count, options: .storageModeShared),
                      let fwBuffer = device.makeBuffer(length: self.pixelSize * MemoryLayout<Float>.stride, options: .storageModeShared),
                      let finalBuffer = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let maxMinBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 2, options: .storageModeShared),
                      let ggBuffer = device.makeBuffer(length: self.pixelSize * MemoryLayout<Float>.stride, options: .storageModeShared),
                      let ptBuffer = device.makeBuffer(length: 256 * MemoryLayout<UInt32>.stride, options: .storageModeShared),
                      let lowHighBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 2, options: .storageModeShared)  else{
                        throw ASError.gpuBufferErr
                }
                
                self.grayBufferPreA = bufferPreA
                self.grayBufferCurA = bufferA
                self.gradientBufferTA = bufferTA
                self.gradientBufferXA = bufferXA
                self.gradientBufferYA = bufferYA
                
                self.grayBufferPreB = bufferPreB
                self.grayBufferCurB = bufferB
                self.gradientBufferTB = bufferTB
                self.gradientBufferXB = bufferXB
                self.gradientBufferYB = bufferYB
                
                self.projectionBuf = pBuffer
                self.fullWtlInOneBuffer = fwBuffer
                self.finalImgBuffer = finalBuffer
                self.maxMinBuffer = maxMinBuffer
                self.gradientMagnitude = ggBuffer
                self.percentileBuffer = ptBuffer
                self.percentileLowHighBuffer = lowHighBuffer
                
                pixelThreadGrpNo = MTLSize(width: (self.videoWidth + PixelThreadWidth - 1) / PixelThreadWidth,
                                           height: (self.videoHeight + PixelThreadHeight - 1) / PixelThreadHeight,
                                           depth: 1)
                
                self.numGroupsMaxMin = MTLSize(width: (self.pixelSize + threadGroupSizeForMaxMin - 1) / threadGroupSizeForMaxMin, height: 1, depth: 1)
                self.numGrpPercentile = MTLSize(width: (self.pixelSize + threadGroupSizeForMaxMin - 1) / threadGroupSizeForMaxMin, height: 1, depth: 1)
        }
        
        private func prepareBlockBuffer(level:Int) throws{
                
                let blockNoInOneDesc = DescriptorParam_M * DescriptorParam_m
                let blockSize = ( SideSizeOfLevelZero << level) / blockNoInOneDesc
                self.numBlocksX[level] = (self.videoWidth + blockSize - 1) / blockSize
                self.numBlocksY[level] = (self.videoHeight + blockSize - 1) / blockSize
                self.numBlockNo[level] = self.numBlocksX[level]  * self.numBlocksY[level]  * HistogramSize
                self.blockSizeInPixel[level] = blockSize
                
                blockThreadGrpSize[level] =  MTLSize(width: blockNoInOneDesc,
                                                     height: blockNoInOneDesc,
                                                     depth: 1)
                blockThreadGrpNo[level] = MTLSize(
                        width: (numBlocksX[level] + blockNoInOneDesc - 1) / blockNoInOneDesc,
                        height: (numBlocksY[level] + blockNoInOneDesc - 1) / blockNoInOneDesc,
                        depth: 1
                )
                
                self.descriptorNumY[level] =  self.numBlocksY [level] - blockNoInOneDesc + 1
                self.descriptorNumX[level] = self.numBlocksX[level]  - blockNoInOneDesc + 1
                self.descriptorNo[level] = self.descriptorNumY[level]  * self.descriptorNumX[level]
                
                self.descriptorThreadGrpNo[level] = MTLSize(
                        width: (self.descriptorNumX[level]  + 7) / 8,
                        height: (self.descriptorNumY[level]  + 7) / 8,
                        depth: 1
                )
                guard let avgGradientAllBlockA = device.makeBuffer(length: numBlockNo[level]  * MemoryLayout<Float>.stride, options: .storageModeShared),
                      let avgGradientAllBlockB = device.makeBuffer(length: numBlockNo[level]  * MemoryLayout<Float>.stride, options: .storageModeShared)else{
                        throw ASError.gpuBufferErr
                }
                
                self.avgGradientOfBlockA[level] = avgGradientAllBlockA
                self.avgGradientOfBlockB[level] = avgGradientAllBlockB
                
                guard let descriptorA = device.makeBuffer(length: self.descriptorNo[level]  * DescriptorSize * MemoryLayout<Float>.stride, options: .storageModeShared),
                      let descriptorB = device.makeBuffer(length: self.descriptorNo[level]  * DescriptorSize * MemoryLayout<Float>.stride, options: .storageModeShared),
                      let wtl = device.makeBuffer(length: self.descriptorNo[level] * MemoryLayout<Float>.stride, options: .storageModeShared),
                      let fwBuffer = device.makeBuffer(length: self.pixelSize * MemoryLayout<Float>.stride, options: .storageModeShared) else{
                        throw ASError.gpuBufferErr
                }
                
#if TmpDescData
                self.descriptorBufferA[level] = descriptorA
                self.descriptorBufferB[level] = descriptorB
#endif
                self.wtlOfAllLevel[level] = wtl
                self.fullWtlBuffer[level] = fwBuffer
        }
        
        private func resetGpuBuffer(){
                memset(grayBufferPreA?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(grayBufferCurA?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferTA?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferXA?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(gradientBufferYA?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                
                memset(grayBufferPreB?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(grayBufferCurB?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferTB?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferXB?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(gradientBufferYB?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(fullWtlInOneBuffer?.contents(), 0, self.pixelSize * MemoryLayout<Float>.stride)
                memset(finalImgBuffer?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(maxMinBuffer?.contents(), 0, 2 * MemoryLayout<UInt8>.stride)
                
                memset(gradientMagnitude?.contents(), 0, self.pixelSize * MemoryLayout<Float>.stride)
                memset(percentileLowHighBuffer?.contents(), 0, 2 * MemoryLayout<UInt8>.stride)
                memset(percentileBuffer?.contents(), 0, 256 * MemoryLayout<UInt32>.stride)
                
                
                for i in 0..<3{
                        memset(avgGradientOfBlockA[i]?.contents(), 0, numBlockNo[i]   * MemoryLayout<Float>.stride)
                        memset(avgGradientOfBlockB[i]?.contents(), 0, numBlockNo[i]   * MemoryLayout<Float>.stride)
#if TmpDescData
                        memset(descriptorBufferA[i]?.contents(), 0, descriptorNo[i] * DescriptorSize * MemoryLayout<Float>.stride)
                        memset(descriptorBufferB[i]?.contents(), 0, descriptorNo[i]  * DescriptorSize * MemoryLayout<Float>.stride)
#endif
                        memset(wtlOfAllLevel[i]?.contents(), 0, descriptorNo[i] * MemoryLayout<Float>.stride)
                        memset(fullWtlBuffer[i]?.contents(), 0, self.pixelSize * MemoryLayout<Float>.stride)
                }
        }
        
     
        private func processVideo() async throws{
                var counter = 0;
                
                var preFrameA:MTLTexture? = nil
                var preFrameB:MTLTexture? = nil
                
                try  self.prepareFrameBuffer();
                for i in 0..<3{
                        try self.prepareBlockBuffer(level: i)
                }
                
                try await iterateVideoFrame(){frameA, frameB in
                        
                        counter+=1
                        self.logProcessInfo("处理第\(counter)帧")
                        if preFrameA == nil{
                                preFrameA = frameA
                                preFrameB = frameB
                                return true
                        }
                        
                        self.resetGpuBuffer()
                        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else{
                                throw  ASError.gpuBufferErr
                        }
                        
                        try self.pixelGradient(preFrame: preFrameA!, curFrame: frameA,
                                               preFrameB: preFrameB!, curFrameB: frameB,
                                               commandBuffer: commandBuffer)
                        for i in 0..<3{
                                
                                try self.avgBlockGradient(commandBuffer: commandBuffer, level: i)
#if TmpDescData
                                try self.normalizedDescriptor(commandBuffer:commandBuffer, level: i)
#endif
                                try self.distanceOfDiscriptor(commandBuffer: commandBuffer, level: i)
                                
                                try self.biLinearInterpolate(commandBuffer: commandBuffer, level: i)
                                
                        }

                        commandBuffer.commit()
                        commandBuffer.waitUntilCompleted()
                        
                        let (min, max) = findMinMax(buffer: self.fullWtlInOneBuffer!, length: self.pixelSize)
                        let pointer = self.maxMinBuffer!.contents().bindMemory(to: Float.self, capacity: 2)
                        pointer[0] = min
                        pointer[1] = max
                        
#if CompareJsonData
                        saveRawDataToFile(fileName: "gpu_wtl_2_billinear_final_.json", buffer: self.fullWtlInOneBuffer!,
                                          width: self.videoWidth, height: self.videoHeight,  type: Float.self)
                        
                        print("cpu min:\(min) max:\(max)")
#endif
                        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else{
                                throw  ASError.gpuBufferErr
                        }
                        try self.normalizeFullWtl(commandBuffer: commandBuffer)
                        
                        try self.percentileOfFrameA(commandBuffer: commandBuffer)
                        
                        commandBuffer.commit()
                        commandBuffer.waitUntilCompleted()
                        
#if CompareJsonData
                        let resultPointer = self.maxMinBuffer!.contents().assumingMemoryBound(to: Float.self)
                        let minVal = resultPointer[0]
                        let maxVal = resultPointer[1]
                        print("min max from gpu:min=\(minVal) max=\(maxVal)")
                        
                        let outputPointer = self.percentileLowHighBuffer?.contents().bindMemory(to: UInt32.self, capacity: 2)
                        let lowVal = outputPointer?[0] ?? 0
                        let highVal = outputPointer?[1] ?? 0
                        print("lowVal or highVal from gpu:lowVal=\(lowVal) max=\(highVal)")
                        self.debugFrameDataToJson(counter: counter)
#endif
                        return false;//true
                }
        }
        
        func pixelGradient(preFrame:MTLTexture, curFrame:MTLTexture, preFrameB:MTLTexture, curFrameB:MTLTexture,commandBuffer:MTLCommandBuffer) throws{
                
                guard let grayCoder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                grayCoder.setComputePipelineState(self.grayAndDiffPipe)
                
                
                grayCoder.setTexture(preFrame, index: 0)
                grayCoder.setTexture(curFrame, index: 1)
                grayCoder.setTexture(preFrameB, index: 2)
                grayCoder.setTexture(curFrameB, index: 3)
                
                grayCoder.setBuffer(grayBufferPreA, offset: 0, index: 0)
                grayCoder.setBuffer(grayBufferCurA, offset: 0, index: 1)
                grayCoder.setBuffer(gradientBufferTA, offset: 0, index: 2)
                grayCoder.setBuffer(grayBufferPreB, offset: 0, index: 3)
                grayCoder.setBuffer(grayBufferCurB, offset: 0, index: 4)
                grayCoder.setBuffer(gradientBufferTB, offset: 0, index: 5)
                
                grayCoder.dispatchThreadgroups(pixelThreadGrpNo!,
                                               threadsPerThreadgroup: pixelThreadGrpSize)
                grayCoder.endEncoding()
                
                guard let gradeintCoder = commandBuffer.makeComputeCommandEncoder() else{
                        throw ASError.gpuEncoderErr
                }
                
                gradeintCoder.setComputePipelineState(spaceGradientPipe)
                gradeintCoder.setBuffer(grayBufferCurA, offset: 0, index: 0)
                gradeintCoder.setBuffer(gradientBufferXA, offset: 0, index: 1)
                gradeintCoder.setBuffer(gradientBufferYA, offset: 0, index: 2)
                gradeintCoder.setBuffer(grayBufferCurB, offset: 0, index: 3)
                gradeintCoder.setBuffer(gradientBufferXB, offset: 0, index: 4)
                gradeintCoder.setBuffer(gradientBufferYB, offset: 0, index: 5)
                var w = self.videoWidth
                var h = self.videoHeight
                gradeintCoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 6)
                gradeintCoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 7)
                var alphaVar = Overlay_Param_Alpha
                gradeintCoder.setBytes(&alphaVar, length: MemoryLayout<Float>.size, index: 8)
                gradeintCoder.setBuffer(gradientMagnitude, offset: 0, index: 9)
                
                gradeintCoder.dispatchThreadgroups(pixelThreadGrpNo!,
                                                   threadsPerThreadgroup: pixelThreadGrpSize)
                gradeintCoder.endEncoding()
        }
        
        func avgBlockGradient(commandBuffer:MTLCommandBuffer, level:Int) throws{
                
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(self.averageBlockGradientPipe)
                
                coder.setBuffer(gradientBufferXA, offset: 0, index: 0)
                coder.setBuffer(gradientBufferYA, offset: 0, index: 1)
                coder.setBuffer(gradientBufferTA, offset: 0, index: 2)
                coder.setBuffer(avgGradientOfBlockA[level], offset: 0, index: 3)
                
                coder.setBuffer(gradientBufferXB, offset: 0, index: 4)
                coder.setBuffer(gradientBufferYB, offset: 0, index: 5)
                coder.setBuffer(gradientBufferTB, offset: 0, index: 6)
                coder.setBuffer(avgGradientOfBlockB[level], offset: 0, index: 7)
                
                coder.setBuffer(self.projectionBuf, offset: 0, index: 8)
                
                coder.setBytes(&self.videoWidth, length: MemoryLayout<Int>.size, index: 9)
                coder.setBytes(&self.videoHeight, length: MemoryLayout<Int>.size, index: 10)
                coder.setBytes(&(self.blockSizeInPixel[level]), length: MemoryLayout<Int>.size, index: 11)
                coder.setBytes(&(numBlocksX[level]), length: MemoryLayout<Int>.size, index: 12)
                
                coder.dispatchThreadgroups(blockThreadGrpNo[level]!,
                                           threadsPerThreadgroup: blockThreadGrpSize[level]!)
                coder.endEncoding()
        }
        
#if TmpDescData
        func normalizedDescriptor(commandBuffer:MTLCommandBuffer, level:Int) throws{
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(self.descriptorPipe)
                
                coder.setBuffer(avgGradientOfBlockA[level], offset: 0, index: 0)
                coder.setBuffer(avgGradientOfBlockB[level], offset: 0, index: 1)
                
                coder.setBuffer(descriptorBufferA[level], offset: 0, index: 2)
                coder.setBuffer(descriptorBufferB[level], offset: 0, index: 3)
                
                coder.setBytes(&(self.descriptorNumX[level]), length: MemoryLayout<Int>.size, index: 4)
                coder.setBytes(&(self.descriptorNumY[level]), length: MemoryLayout<Int>.size, index: 5)
                var levelVar = level
                coder.setBytes(&levelVar, length: MemoryLayout<Int>.size, index: 6)
                coder.setBytes(&(numBlocksX[level]), length: MemoryLayout<Int>.size, index: 7)
                
                coder.dispatchThreadgroups(descriptorThreadGrpNo[level]!,
                                           threadsPerThreadgroup: descriptorThreadGrpSize)
                coder.endEncoding()
        }
#endif
        
        func distanceOfDiscriptor(commandBuffer:MTLCommandBuffer, level:Int) throws{
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(self.wtlPipe)
                
                coder.setBuffer(avgGradientOfBlockA[level], offset: 0, index: 0)
                coder.setBuffer(avgGradientOfBlockB[level], offset: 0, index: 1)
                
                coder.setBuffer(wtlOfAllLevel[level], offset: 0, index: 2)
                
                coder.setBytes(&(self.descriptorNumX[level]), length: MemoryLayout<Int>.size, index: 3)
                coder.setBytes(&(self.descriptorNumY[level]), length: MemoryLayout<Int>.size, index: 4)
                var levelVar = level
                coder.setBytes(&levelVar, length: MemoryLayout<Int>.size, index:5)
                coder.setBytes(&(numBlocksX[level]), length: MemoryLayout<Int>.size, index: 6)
                
                coder.dispatchThreadgroups(descriptorThreadGrpNo[level]!,
                                           threadsPerThreadgroup: descriptorThreadGrpSize)
                coder.endEncoding()
        }
        
        func biLinearInterpolate(commandBuffer:MTLCommandBuffer, level:Int) throws{
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(self.biLinearPipe)
                
                coder.setBuffer(self.wtlOfAllLevel[level], offset: 0, index: 0)
                coder.setBuffer(self.fullWtlInOneBuffer, offset: 0, index: 1)
                coder.setBytes(&self.videoWidth, length: MemoryLayout<Int>.size, index: 2)
                coder.setBytes(&self.videoHeight, length: MemoryLayout<Int>.size, index: 3)
                var shift =  (SideSizeOfLevelZero << level) / 2
                var descDistanceInPixel = (SideSizeOfLevelZero << level)/DescriptorParam_M/DescriptorParam_m
                coder.setBytes(&descDistanceInPixel, length: MemoryLayout<Int>.size, index:4)
                coder.setBytes(&self.descriptorNumX[level], length: MemoryLayout<Int>.size, index:5)
                coder.setBytes(&self.descriptorNumY[level], length: MemoryLayout<Int>.size, index:6)
                coder.setBytes(&shift, length: MemoryLayout<Int>.size, index:7)
                var levelVar = level
                coder.setBytes(&levelVar, length: MemoryLayout<Int>.size, index:8)
                var useTmp = true
#if DEBUGTMPWTL
                useTmp = true
                coder.setBytes(&useTmp, length: MemoryLayout<Bool>.size, index: 9)
                coder.setBuffer(self.fullWtlBuffer[level], offset: 0, index: 10)
#else
                useTmp = false
                coder.setBytes(&useTmp, length: MemoryLayout<Bool>.size, index: 9)
                coder.setBuffer(self.fullWtlBuffer[level], offset: 0, index: 10)
#endif
                coder.dispatchThreadgroups(pixelThreadGrpNo!,
                                           threadsPerThreadgroup: pixelThreadGrpSize)
                coder.endEncoding()
        }
        
        func findMinMaxVal(commandBuffer:MTLCommandBuffer) throws{
                guard let maxMinCoder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                maxMinCoder.setComputePipelineState(self.maxMinPipe)
                maxMinCoder.setBuffer(self.fullWtlInOneBuffer, offset: 0, index: 0)
                maxMinCoder.setBuffer(self.maxMinBuffer, offset: 0, index: 1)
                
                var totalElements = self.pixelSize
                maxMinCoder.setBytes(&totalElements, length: MemoryLayout<UInt>.size, index: 2)
                
                var totalGroups = self.numGroupsMaxMin!.width
                maxMinCoder.setBytes(&totalGroups, length: MemoryLayout<UInt>.size, index: 3)
                
                var groupSize = self.threadsPerGroupMaxMin.width
                maxMinCoder.setBytes(&groupSize, length: MemoryLayout<UInt>.size, index: 4)
                
                maxMinCoder.setThreadgroupMemoryLength(threadGroupSizeForMaxMin * MemoryLayout<Float>.size, index: 0) // 对于localMin
                maxMinCoder.setThreadgroupMemoryLength(threadGroupSizeForMaxMin * MemoryLayout<Float>.size, index: 1) // 对于localMax
                
                maxMinCoder.dispatchThreadgroups(numGroupsMaxMin!, threadsPerThreadgroup: threadsPerGroupMaxMin)
                maxMinCoder.endEncoding()
        }
        
        func normalizeFullWtl(commandBuffer:MTLCommandBuffer) throws{
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                coder.setComputePipelineState(self.normlizePipe)
                coder.setBuffer(self.fullWtlInOneBuffer, offset: 0, index: 0)
                coder.setBuffer(self.maxMinBuffer, offset: 0, index: 1)
                coder.setBytes(&self.videoWidth, length: MemoryLayout<Int>.size, index: 2)
                coder.setBytes(&self.videoHeight, length: MemoryLayout<Int>.size, index: 3)
                coder.dispatchThreadgroups(pixelThreadGrpNo!,
                                           threadsPerThreadgroup: pixelThreadGrpSize)
                coder.endEncoding()
        }
        
        func percentileOfFrameA(commandBuffer:MTLCommandBuffer) throws{
                
                guard let histoCoder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                histoCoder.setComputePipelineState(self.percentileHistogramPipe)
                histoCoder.setBuffer(self.grayBufferCurA, offset: 0, index: 0)
                histoCoder.setBuffer(self.percentileBuffer, offset: 0, index: 1)
                var totalElements = self.pixelSize
                histoCoder.setBytes(&totalElements, length: MemoryLayout<UInt>.size, index: 2)
                
                histoCoder.dispatchThreadgroups(self.numGrpPercentile!, threadsPerThreadgroup: threadsPerGroupMaxMin)
                histoCoder.endEncoding()
                
                guard let percentCoder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                percentCoder.setComputePipelineState(self.percentilePipe)
                percentCoder.setBuffer(self.percentileBuffer, offset: 0, index: 0)
                percentCoder.setBytes(&totalElements, length: MemoryLayout<UInt>.size, index: 1)
                
                var lowPerc = Overlay_Low_Perc
                var highPerc = Overlay_High_Perc
                percentCoder.setBytes(&lowPerc, length: MemoryLayout<Float>.size, index: 2)
                percentCoder.setBytes(&highPerc, length: MemoryLayout<Float>.size, index: 3)
                percentCoder.setBuffer(self.percentileLowHighBuffer, offset: 0, index: 4)
                
                percentCoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                percentCoder.endEncoding()
        }
}


extension  VideoCompare{
        
        private func pixelBufferToTexture(_ sbuf: CMSampleBuffer)->MTLTexture?{
                
                guard let videoFrame = CMSampleBufferGetImageBuffer(sbuf) else{
                        return nil
                }
                guard let inputTexture = device.makeTexture(descriptor: textureDescriptor) else {
                        print("Error: Failed to create input texture")
                        return nil
                }
                
                let ciImage = CIImage(cvPixelBuffer: videoFrame)
                let context = CIContext(mtlDevice: device)
                context.render(ciImage, to: inputTexture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                
                return inputTexture
        }
        
        private func iterateVideoFrame(callBack: ((MTLTexture,MTLTexture)throws -> Bool)?) async throws{
                let readerA = try AVAssetReader(asset: self.assetA)
                let readerB = try AVAssetReader(asset: self.assetB)
                guard let videoTrackA = try await self.assetA.loadTracks(withMediaType: .video).first,
                      let videoTrackB = try await self.assetB.loadTracks(withMediaType: .video).first else {
                        throw ASError.noValidVideoTrack
                }
                
                let trackReaderOutputA = AVAssetReaderTrackOutput(track: videoTrackA, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                let trackReaderOutputB = AVAssetReaderTrackOutput(track: videoTrackB, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                readerA.add(trackReaderOutputA)
                readerB.add(trackReaderOutputB)
                readerA.startReading()
                readerB.startReading()
                
                while let sampleBufferA = trackReaderOutputA.copyNextSampleBuffer(),
                      let sampleBufferB = trackReaderOutputB.copyNextSampleBuffer(){
                        guard  let frameA = pixelBufferToTexture(sampleBufferA),
                               let frameB = pixelBufferToTexture(sampleBufferB)else{
                                throw ASError.readVideoDataFailed
                        }
                        if let callBack = callBack {
                                let conitune = try callBack(frameA,frameB)
                                if !conitune{
                                        break
                                }
                        }
                }
                readerA.cancelReading()
                readerB.cancelReading()
                self.logProcessInfo("视频处理完成")
        }
        
        private func logProcessInfo(_ info:String){
                DispatchQueue.main.async { self.processingMessage = info}
        }
        
#if CompareJsonData
        private func debugFrameDataToJson(counter:Int){
                
                
                saveRawDataToFile(fileName: "gpu_gradient_magnitude_\(counter)_.json", buffer: gradientMagnitude!,
                                  width: self.videoWidth, height: self.videoHeight,  type: Float.self)
                
                saveRawDataToFile(fileName: "gpu_percentile_\(counter)_histogram_.json", buffer: self.percentileBuffer!, width: 256, height: 1, type: UInt32.self)
                
                for i in 0..<3{
                        
                        saveRawDataToFileWithDepth(fileName: "gpu_average_block_\(counter)_a_level_\(i).json",
                                                   buffer: self.avgGradientOfBlockA[i]!,
                                                   width: self.numBlocksX[i], height: self.numBlocksY[i],
                                                   depth: HistogramSize, type: Float.self)
                        
                        saveRawDataToFileWithDepth(fileName: "gpu_average_block_\(counter)_b_level_\(i).json",
                                                   buffer: self.avgGradientOfBlockB[i]!,
                                                   width: self.numBlocksX[i], height: self.numBlocksY[i],
                                                   depth: HistogramSize, type: Float.self)
                        
#if TmpDescData
                        saveRawDataToFileWithDepth(fileName: "gpu_descriptor_\(counter)_a_level_\(i).json",
                                                   buffer: self.descriptorBufferA[i]!,
                                                   width: self.descriptorNumX[i], height: self.descriptorNumY[i],
                                                   depth: DescriptorSize, type: Float.self)
                        
                        saveRawDataToFileWithDepth(fileName: "gpu_descriptor_\(counter)_b_level_\(i).json",
                                                   buffer: self.descriptorBufferB[i]!,
                                                   width: self.descriptorNumX[i], height: self.descriptorNumX[i],
                                                   depth: DescriptorSize, type: Float.self)
#endif
                        
                        saveRawDataToFile(fileName: "gpu_wtl_\(counter)_level_\(i).json", buffer: wtlOfAllLevel[i]!,
                                          width: self.descriptorNumX[i], height: self.descriptorNumY[i],  type: Float.self)
                        
                        
#if DEBUGTMPWTL
                        saveRawDataToFile(fileName: "gpu_wtl_\(counter)_billinear_\(i).json", buffer: fullWtlBuffer[i]!,
                                          width: self.videoWidth, height: self.videoHeight,  type: Float.self)
#endif
                }
                
                saveRawDataToFile(fileName: "gpu_wtl_\(counter)_billinear_final_normalized_.json", buffer: fullWtlInOneBuffer!,
                                  width: self.videoWidth, height: self.videoHeight,  type: Float.self)
        }
#endif
}
