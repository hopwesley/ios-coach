//
//  AlignController.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/21.
//

import Foundation
import AVFoundation
import CoreImage
class AlignController: ObservableObject {
        
        @Published var videoURL: URL?
        @Published var videoInfo:String?
        
        var videoWidth:Double = 0
        var videoHeight:Double = 0
        var videoTrack: AVAssetTrack!
        
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var alignPipelineState: MTLComputePipelineState!
        var textureDescriptor:MTLTextureDescriptor!
        init() {
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                
                let library = device.makeDefaultLibrary()
                
                let quantizeFunc = library?.makeFunction(name: "frameQValByBlock")
                alignPipelineState = try! device.makeComputePipelineState(function: quantizeFunc!)
        }
        
        func removeVideo(){
                if let url = self.videoURL{
                        deleteFile(at: url)
                }
                self.videoURL = nil
        }
        
        func prepareVideoInBackground(url:URL){
                DispatchQueue.main.async {
                        self.videoURL = url
                }
                Task{
                        do{
                                try await  self.parseVideo(url: url)
                        }catch{
                                DispatchQueue.main.async {
                                        self.videoInfo =  error.localizedDescription
                                }
                        }
                }
        }
        
        func parseVideo(url:URL) async throws{
                
                let asset = AVAsset(url: url)
                let d = try await asset.load(.duration)
                let duration = CMTimeGetSeconds(d)
                if duration > constMaxVideoLen{
                        throw VideoParsingError.videoTooLong
                }
                
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        throw VideoParsingError.noValidVideoTrack
                }
                
                self.videoTrack = videoTrack
                let videoSize = try await videoTrack.load(.naturalSize)
                self.videoWidth = videoSize.width
                self.videoHeight = videoSize.height
                
                DispatchQueue.main.async {
                        self.videoInfo =  "width(\(self.videoWidth)) height(\(self.videoHeight)) duration(\(duration) )seconds"
                }
                
                self.textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: Int(videoSize.width),
                        height: Int(videoSize.height),
                        mipmapped: false
                )
                textureDescriptor.usage = [.shaderRead, .shaderWrite]
        }
        
        func histogramOfAllFrame()->MTLBuffer?{
                return nil
        }
        
        private func pixelBufferToTexture(videoFrame: CVPixelBuffer)->MTLTexture?{
                guard let inputTexture = device.makeTexture(descriptor: textureDescriptor) else {
                        print("Error: Failed to create input texture")
                        return nil
                }
                
                let ciImage = CIImage(cvPixelBuffer: videoFrame)
                let context = CIContext(mtlDevice: device)
                context.render(ciImage, to: inputTexture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                
                return inputTexture
        }
        
        func AlignVideo(){
                Task{
                        do{
                                try tryAlignFirstImg()
                        }catch{
                                DispatchQueue.main.async {
                                        self.videoInfo =  error.localizedDescription
                                }
                        }
                }
        }
        
        private func tryAlignFirstImg() throws{
                
                let trackOutput = AVAssetReaderTrackOutput(track: self.videoTrack, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                let asset = AVAsset(url: self.videoURL!)
                let reader = try AVAssetReader(asset: asset)
                reader.add(trackOutput)
                reader.startReading()
                //                        while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
                // 读取视频的第一个帧数据
                guard let sampleBufferA = trackOutput.copyNextSampleBuffer(),
                      let pixelBufferA = CMSampleBufferGetImageBuffer(sampleBufferA),
                      let textA = pixelBufferToTexture(videoFrame: pixelBufferA) else{
                        throw VideoParsingError.readVideoDataFailed
                }
                guard let sampleBufferB = trackOutput.copyNextSampleBuffer(),
                      let pixelBufferB = CMSampleBufferGetImageBuffer(sampleBufferB),
                      let textB = pixelBufferToTexture(videoFrame: pixelBufferB) else{
                        throw VideoParsingError.readVideoDataFailed
                }
                
                let S_0 = 32
                let blockSize = S_0/DescriptorParam_M/DescriptorParam_m
                guard let finalQuantity = quantizeFrameByBlockGradient(device: device,
                                                                       commandQueue: commandQueue,
                                                                       pipelineState: alignPipelineState,
                                                                       rawImgA: textA,
                                                                       rawImgB: textB,
                                                                       width: Int(self.videoWidth),
                                                                       height: Int(self.videoHeight),
                                                                       blockSize:blockSize) else{
                        print("------>>> computeGradientProjections  failed");
                        return;
                }
                let numBlocksX = (Int(self.videoWidth) + blockSize - 1) / blockSize
                let numBlocksY = (Int(self.videoHeight) + blockSize - 1) / blockSize
                saveRawDataToFileWithDepth(fileName: "gpu_block_gradient_\(S_0).json",
                                           buffer: finalQuantity,
                                           width: numBlocksX,
                                           height: numBlocksY,
                                           depth: 10,
                                           type: Float.self)
                
        }
}
