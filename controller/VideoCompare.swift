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
        var numBlocksX:Int = 0
        var numBlocks:Int = 0
        var numBlocksY:Int = 0
        var blockSizeInPixel:Int = 0
        
        var textureDescriptor:MTLTextureDescriptor!
        var assetA:AVAsset!
        var assetB:AVAsset!
        
        var device:MTLDevice!
        var commandQueue: MTLCommandQueue!
        
        var grayAndDiffPipe: MTLComputePipelineState!
        var spaceGradientPipe: MTLComputePipelineState!
        var blockHistogramPipe: MTLComputePipelineState!
        
        var grayBufferPreB:MTLBuffer?
        var grayBufferCurB:MTLBuffer?
        var gradientBufferXB:MTLBuffer?
        var gradientBufferYB:MTLBuffer?
        var gradientBufferTB:MTLBuffer?
        var avgGradientOfBlockB:MTLBuffer?
        
        var grayBufferPreA:MTLBuffer?
        var grayBufferCurA:MTLBuffer?
        var gradientBufferXA:MTLBuffer?
        var gradientBufferYA:MTLBuffer?
        var gradientBufferTA:MTLBuffer?
        var avgGradientOfBlockA:MTLBuffer?
        
        
        var projectionBuf:MTLBuffer?
        
        var pixelThreadGrpNo:MTLSize?
        var pixelThreadGrpSize:MTLSize = MTLSize(width: PixelThreadWidth,
                                                 height: PixelThreadHeight,
                                                 depth: 1)
        var blockThreadGrpSize:MTLSize?
        var blockThreadGrpNo:MTLSize?
        
        func CompareAction(videoA:URL,videoB:URL)async throws{
                self.assetA = AVAsset(url: videoA)
                self.assetB = AVAsset(url: videoB)
                
                logProcessInfo("初始化GPU")
                try initGpuDevice()
                try await self.prepareVideoParam()
                try  self.prepareFrameBuffer();
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
                      let quantizeGradientFun = library.makeFunction(name: "quantizeAvgerageGradientOfTwoBlock") else{
                        throw ASError.shaderLoadErr
                }
                
                grayAndDiffPipe = try device.makeComputePipelineState(function: grayAndDiff)
                spaceGradientPipe = try device.makeComputePipelineState(function: spaceGradientFun)
                blockHistogramPipe = try device.makeComputePipelineState(function: quantizeGradientFun)
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
                      let pBuffer = device.makeBuffer(bytes: normalizedP,
                                                      length: MemoryLayout<SIMD3<Float>>.stride * normalizedP.count, options: .storageModeShared) else{
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
                
                pixelThreadGrpNo = MTLSize(width: (self.videoWidth + PixelThreadWidth - 1) / PixelThreadWidth,
                                           height: (self.videoHeight + PixelThreadHeight - 1) / PixelThreadHeight,
                                           depth: 1)
        }
        
        private func prepareBlockBuffer(sideOfDesc:Int) throws{
                
                let blockSideOneDesc = DescriptorParam_M * DescriptorParam_m
                let blockSize = sideOfDesc / blockSideOneDesc
                self.numBlocksX = (self.videoWidth + blockSize - 1) / blockSize
                self.numBlocksY = (self.videoHeight + blockSize - 1) / blockSize
                self.numBlocks = self.numBlocksX * numBlocksY
                self.blockSizeInPixel = blockSize
                let histogramLen = numBlocks * HistogramSize * MemoryLayout<Float>.stride
                
                guard let avgGradientAllBlockA = device.makeBuffer(length: histogramLen, options: .storageModeShared),
                      let avgGradientAllBlockB = device.makeBuffer(length: histogramLen, options: .storageModeShared)else{
                        throw ASError.gpuBufferErr
                }
                self.avgGradientOfBlockA = avgGradientAllBlockA
                self.avgGradientOfBlockB = avgGradientAllBlockB
                
                blockThreadGrpSize =  MTLSize(width: blockSideOneDesc,
                                              height: blockSideOneDesc,
                                              depth: 1)
                blockThreadGrpNo = MTLSize(
                        width: (numBlocksX + blockSideOneDesc - 1) / blockSideOneDesc,
                        height: (numBlocksY + blockSideOneDesc - 1) / blockSideOneDesc,
                        depth: 1
                )
        }
        
        private func resetBuffer(){
                memset(grayBufferPreA?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(grayBufferCurA?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferTA?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferXA?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(gradientBufferYA?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(avgGradientOfBlockA?.contents(), 0, numBlocks * HistogramSize * MemoryLayout<Float>.stride)
                
                
                memset(grayBufferPreB?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(grayBufferCurB?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferTB?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferXB?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(gradientBufferYB?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(avgGradientOfBlockB?.contents(), 0, numBlocks * HistogramSize * MemoryLayout<Float>.stride)
        }
        
        private func processVideo() async throws{
                var counter = 0;
                
                var preFrameA:MTLTexture? = nil
                var preFrameB:MTLTexture? = nil
                
                try await iterateVideoFrame(){frameA, frameB in
                        
                        counter+=1
                        self.logProcessInfo("处理第\(counter)帧")
                        if preFrameA == nil{
                                preFrameA = frameA
                                preFrameB = frameB
                                return true
                        }
                        
                        self.resetBuffer()
                        
                        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else{
                                throw  ASError.gpuBufferErr
                        }
                        
                        try self.prepareBlockBuffer(sideOfDesc: 32)
                        try self.pixelGradient(preFrame: preFrameA!, curFrame: frameA,
                                               preFrameB: preFrameB!, curFrameB: frameB,
                                               commandBuffer: commandBuffer)
                        
                        try self.avgBlockGradient(commandBuffer: commandBuffer)
                        
                        commandBuffer.commit()
                        commandBuffer.waitUntilCompleted()
#if DEBUG
                        saveRawDataToFileWithDepth(fileName: "gpu_average_block_\(self.blockSizeInPixel)_\(counter)_a.json",
                                                   buffer: self.avgGradientOfBlockA!,
                                                   width: self.numBlocksX, height: self.numBlocksY,
                                                   depth: HistogramSize, type: Float.self)
                        
                        saveRawDataToFileWithDepth(fileName: "gpu_average_block_\(self.blockSizeInPixel)_\(counter)_b.json",
                                                   buffer: self.avgGradientOfBlockB!,
                                                   width: self.numBlocksX, height: self.numBlocksY,
                                                   depth: HistogramSize, type: Float.self)
#endif
                        return false;
                        //                        return true;
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
                
                gradeintCoder.dispatchThreadgroups(pixelThreadGrpNo!,
                                                   threadsPerThreadgroup: pixelThreadGrpSize)
                gradeintCoder.endEncoding()
        }
        
        func avgBlockGradient(commandBuffer:MTLCommandBuffer) throws{
                
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(self.blockHistogramPipe)
                
                coder.setBuffer(gradientBufferXA, offset: 0, index: 0)
                coder.setBuffer(gradientBufferYA, offset: 0, index: 1)
                coder.setBuffer(gradientBufferTA, offset: 0, index: 2)
                coder.setBuffer(avgGradientOfBlockA, offset: 0, index: 3)
                
                coder.setBuffer(gradientBufferXB, offset: 0, index: 4)
                coder.setBuffer(gradientBufferYB, offset: 0, index: 5)
                coder.setBuffer(gradientBufferTB, offset: 0, index: 6)
                coder.setBuffer(avgGradientOfBlockB, offset: 0, index: 7)
                
                coder.setBuffer(self.projectionBuf, offset: 0, index: 8)
                
                coder.setBytes(&self.videoWidth, length: MemoryLayout<Int>.size, index: 9)
                coder.setBytes(&self.videoHeight, length: MemoryLayout<Int>.size, index: 10)
                coder.setBytes(&self.blockSizeInPixel, length: MemoryLayout<Int>.size, index: 11)
                coder.setBytes(&numBlocksX, length: MemoryLayout<Int>.size, index: 12)
                
                coder.dispatchThreadgroups(blockThreadGrpNo!,
                                           threadsPerThreadgroup: blockThreadGrpSize!)
                coder.endEncoding()
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
        }
        
        private func logProcessInfo(_ info:String){
                DispatchQueue.main.async { self.processingMessage = info}
        }
}
