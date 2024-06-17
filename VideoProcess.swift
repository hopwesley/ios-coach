//
//  VideoProcess.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/15.
//

import Foundation
import Metal
import AVFoundation
import CoreImage
import UIKit
import MetalKit

class VideoProcess: ObservableObject {
        @Published var videoURL: URL?
        @Published var videoDurationText: String = "00:00"
        @Published var videoFrameCount: Int = 0
        @Published var videoFrameRate: Int = 0
        @Published var grayscaleImage: UIImage?
        
        var videoTextures: [MTLTexture] = []
        var videoGrayTextures: [MTLTexture] = []
        
        var videoTrack:AVAssetTrack!
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var computePipelineState: MTLComputePipelineState!
        
        init() {
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                
                let library = device.makeDefaultLibrary()
                let kernelFunction = library?.makeFunction(name: "grayscaleKernel")
                computePipelineState = try! device.makeComputePipelineState(function: kernelFunction!)
                
        }
        
        func debugGrayResult(){
                
        }
        
        
        func parseTextFromVideo(asset:AVAsset) throws{
                
                self.videoTextures.removeAll()
                let trackOutput = AVAssetReaderTrackOutput(track: self.videoTrack, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                let reader = try AVAssetReader(asset: asset)
                reader.add(trackOutput)
                reader.startReading()
                // 读取视频的第一个帧数据
                        if let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            
                            // 将帧数据转换为灰度图
                            if let grayImage = convertToGrayscale(from: pixelBuffer) {
                                DispatchQueue.main.async {
                                    self.grayscaleImage = grayImage
                                }
                            }
                        }
        }
        
        
        func parseVideoInfo()async throws{
                let frameRate = try await self.videoTrack.load(.nominalFrameRate)
                let timeRange = try await self.videoTrack.load(.timeRange)
                let frameCount = Int(frameRate * Float(timeRange.duration.value) / Float(timeRange.duration.timescale))
                
                DispatchQueue.main.async {
                        self.videoFrameCount = frameCount
                        self.videoFrameRate = Int(round(frameRate))
                }
        }
        
        
        func formatTime(_ seconds: Double) -> String {
                let minutes = Int(seconds) / 60
                let seconds = Int(seconds) % 60
                return String(format: "%02d:%02d", minutes, seconds)
        }
        
        func prepareVideoForGpu(url: URL)  {
                Task {
                        do{
                                let asset = AVAsset(url: url)
                                let d = try await asset.load(.duration)
                                let duration = CMTimeGetSeconds(d)
                                if duration > constMaxVideoLen {
                                        print("视频时长不能超过20秒")
                                        return
                                }
                                
                                DispatchQueue.main.async {
                                        self.videoDurationText = self.formatTime(duration)
                                        self.videoURL = url
                                }
                                
                                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                                        print("No video track found")
                                        return
                                }
                                
                                self.videoTrack = videoTrack
                                
                                try await parseVideoInfo()
                                
                                try parseTextFromVideo(asset: asset)
                                
                        }catch{
                                print("加载视频时长失败: \(error.localizedDescription)")
                        }
                }
        }
        
        func removeVideo() {
                videoURL = nil
        }
        
        func convertToGray() {
                
        }
        
        func reset() {
        }
        
        
        
        func convertToGrayscale(from videoFrame: CVPixelBuffer) -> UIImage? {
                // Create a texture descriptor for the input texture
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: CVPixelBufferGetWidth(videoFrame),
                        height: CVPixelBufferGetHeight(videoFrame),
                        mipmapped: false
                )
                textureDescriptor.usage = [.shaderRead, .shaderWrite]
                let inputTexture = device.makeTexture(descriptor: textureDescriptor)
                
                let ciImage = CIImage(cvPixelBuffer: videoFrame)
                let context = CIContext(mtlDevice: device)
                context.render(ciImage, to: inputTexture!, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                
                // Create an output texture
                let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: inputTexture!.width,
                        height: inputTexture!.height,
                        mipmapped: false
                )
                outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
                let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)
                
                // Create a command buffer and a compute command encoder
                let commandBuffer = commandQueue.makeCommandBuffer()!
                let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
                
                computeEncoder.setComputePipelineState(computePipelineState)
                computeEncoder.setTexture(inputTexture, index: 0)
                computeEncoder.setTexture(outputTexture, index: 1)
                
                let threadGroupSize = MTLSizeMake(8, 8, 1)
                let threadGroups = MTLSizeMake(
                        (inputTexture!.width + threadGroupSize.width - 1) / threadGroupSize.width,
                        (inputTexture!.height + threadGroupSize.height - 1) / threadGroupSize.height,
                        1
                )
                
                computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                computeEncoder.endEncoding()
                
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                
                // Get the grayscale image from the output texture
                return textureToUIImage(texture: outputTexture!)
        }
        
        func textureToUIImage(texture: MTLTexture) -> UIImage? {
                let width = texture.width
                let height = texture.height
                let rowBytes = width * 4
                var imageBytes = [UInt8](repeating: 0, count: rowBytes * height)
                
                let region = MTLRegionMake2D(0, 0, width, height)
                texture.getBytes(&imageBytes, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                let bitsPerComponent = 8
                let bitsPerPixel = 32
                
                let providerRef = CGDataProvider(data: NSData(bytes: &imageBytes, length: imageBytes.count))
                let cgImage = CGImage(
                        width: width,
                        height: height,
                        bitsPerComponent: bitsPerComponent,
                        bitsPerPixel: bitsPerPixel,
                        bytesPerRow: rowBytes,
                        space: colorSpace,
                        bitmapInfo: bitmapInfo,
                        provider: providerRef!,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: .defaultIntent
                )
                
                return UIImage(cgImage: cgImage!)
        }
}
