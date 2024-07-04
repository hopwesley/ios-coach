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
                
                try initGpuDevice()
                try await self.prepareParametersFromeOneVideo()
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
        
        private func iterateVideoFrame(asset:AVAsset,callBack: ((MTLTexture) -> Void)?) async throws{
                let reader = try AVAssetReader(asset: asset)
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        throw ASError.noValidVideoTrack
                }
                
                let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                reader.add(trackReaderOutput)
                reader.startReading()
                
                while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
                        guard  let frame = pixelBufferToTexture(sampleBuffer) else{
                                throw ASError.readVideoDataFailed
                        }
                        if let callBack = callBack {
                                callBack(frame)
                        }
                }
                reader.cancelReading()
        }
        
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
}
