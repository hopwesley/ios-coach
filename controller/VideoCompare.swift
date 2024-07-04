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
        var sideOfBlock:Int = 0
        
        var textureDescriptor:MTLTextureDescriptor!
        var assetA:AVAsset!
        var assetB:AVAsset!
        
        var device:MTLDevice!
        var commandQueue: MTLCommandQueue!
        
        var grayAndDiffPipe: MTLComputePipelineState!
        var spaceGradientPipe: MTLComputePipelineState!
        var blockHistogramPipe: MTLComputePipelineState!
        
        var grayBufferPre:MTLBuffer?
        var grayBufferCur:MTLBuffer?
        var gradientBufferX:MTLBuffer?
        var gradientBufferY:MTLBuffer?
        var gradientBufferT:MTLBuffer?
        var avgGradientOfBlock:MTLBuffer?
        
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
                
                guard let grayAndDiff = library.makeFunction(name: "grayAndTimeDiff"),
                      let spaceGradientFun = library.makeFunction(name: "spaceGradient"),
                      let quantizeGradientFun = library.makeFunction(name: "quantizeAvgerageGradientOfBlock") else{
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
                
                guard let bufferA = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferB = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferT = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let bufferX = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared),
                      let bufferY = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared) else{
                        throw ASError.gpuBufferErr
                }
                
                self.grayBufferPre = bufferA
                self.grayBufferCur = bufferB
                self.gradientBufferT = bufferT
                self.gradientBufferX = bufferX
                self.gradientBufferY = bufferY
                
                pixelThreadGrpNo = MTLSize(width: (self.videoWidth + PixelThreadWidth - 1) / PixelThreadWidth,
                                           height: (self.videoHeight + PixelThreadHeight - 1) / PixelThreadHeight,
                                           depth: 1)
        }
        
        private func prepareBlockBuffer(sideOfDesc:Int) throws{
                
                let blockSideOneDesc = DescriptorParam_M * DescriptorParam_m
                let blockSize = sideOfDesc / blockSideOneDesc
                self.numBlocksX = (self.videoWidth + blockSize - 1) / blockSize
                let numBlocksY = (self.videoHeight + blockSize - 1) / blockSize
                self.numBlocks = self.numBlocksX * numBlocksY
                self.sideOfBlock = blockSize
                let histogramLen = numBlocks * HistogramSize * MemoryLayout<Float>.stride
                
                guard let avgGradientAllBlock = device.makeBuffer(length: histogramLen, options: .storageModeShared) else{
                        throw ASError.gpuBufferErr
                }
                self.avgGradientOfBlock = avgGradientAllBlock
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
                memset(grayBufferPre?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(grayBufferCur?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferT?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferX?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(gradientBufferY?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(avgGradientOfBlock?.contents(), 0, numBlocks * HistogramSize * MemoryLayout<Float>.stride)
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
                                return
                        }
                        
                        self.resetBuffer()
                        
                        try self.prepareFrame(preFrame: preFrameA!, curFrame: frameA)
                        try self.prepareFrame(preFrame: preFrameB!, curFrame: frameB)
                        
                }
        }
        
        func prepareFrame(preFrame:MTLTexture, curFrame:MTLTexture) throws{
                
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let grayCoder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                grayCoder.setComputePipelineState(self.grayAndDiffPipe)
                grayCoder.setTexture(preFrame, index: 0)
                grayCoder.setTexture(curFrame, index: 1)
                grayCoder.setBuffer(grayBufferPre, offset: 0, index: 0)
                grayCoder.setBuffer(grayBufferCur, offset: 0, index: 1)
                grayCoder.setBuffer(gradientBufferT, offset: 0, index: 2)
                grayCoder.dispatchThreadgroups(pixelThreadGrpNo!,
                                           threadsPerThreadgroup: pixelThreadGrpSize)
                grayCoder.endEncoding()
                
                guard let gradeintCoder = commandBuffer.makeComputeCommandEncoder() else{
                        throw ASError.gpuEncoderErr
                }
                
                gradeintCoder.setComputePipelineState(spaceGradientPipe)
                gradeintCoder.setBuffer(grayBufferCur, offset: 0, index: 0)
                gradeintCoder.setBuffer(gradientBufferX, offset: 0, index: 1)
                gradeintCoder.setBuffer(gradientBufferY, offset: 0, index: 2)
                var w = self.videoWidth
                var h = self.videoHeight
                gradeintCoder.setBytes(&w, length: MemoryLayout<Int>.size, index: 3)
                gradeintCoder.setBytes(&h, length: MemoryLayout<Int>.size, index: 4)
                
                gradeintCoder.dispatchThreadgroups(pixelThreadGrpNo!,
                                           threadsPerThreadgroup: pixelThreadGrpSize)
                gradeintCoder.endEncoding()
                
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
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
        
        private func iterateVideoFrame(callBack: ((MTLTexture,MTLTexture)throws -> Void)?) async throws{
                let readerA = try AVAssetReader(asset: self.assetA)
                let readerB = try AVAssetReader(asset: self.assetA)
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
                                try callBack(frameA,frameB)
                        }
                }
                readerA.cancelReading()
                readerB.cancelReading()
        }
        
        private func logProcessInfo(_ info:String){
                DispatchQueue.main.async { self.processingMessage = info}
        }
}
