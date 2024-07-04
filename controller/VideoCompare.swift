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
        var textureDescriptor:MTLTextureDescriptor!
        var assetA:AVAsset!
        var assetB:AVAsset!
        
        var device:MTLDevice!
        var commandQueue: MTLCommandQueue!
        
        var grayAndDiffPipe: MTLComputePipelineState!
        var spaceGradientPipe: MTLComputePipelineState!
        var blockHistogramPipe: MTLComputePipelineState!
        
        func CompareAction(videoA:URL,videoB:URL)async throws{
                self.assetA = AVAsset(url: videoA)
                self.assetB = AVAsset(url: videoB)
                
                logProcessInfo("初始化GPU")
                try initGpuDevice()
                try await self.prepareParametersFromeOneVideo()
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
        
        private func prepareParametersFromeOneVideo() async throws{
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
        
        private func prepareDeviceBuffer(){
                
        }
        
        private func processVideo() async throws{
                var counter = 0;
                try await iterateVideoFrame(){frameA, frameB in
                        counter+=1
                        self.logProcessInfo("处理第\(counter)帧")
                }
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
        
        private func iterateVideoFrame(callBack: ((MTLTexture,MTLTexture) -> Void)?) async throws{
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
                                callBack(frameA,frameB)
                        }
                }
                readerA.cancelReading()
                readerB.cancelReading()
        }
        
        private func logProcessInfo(_ info:String){
                DispatchQueue.main.async { self.processingMessage = info}
        }
}
