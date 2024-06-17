import Foundation
import Metal
import AVFoundation
import CoreImage
import UIKit
import MetalKit

class GrayConverterSingleChannel: ObservableObject {
        @Published var videoURL: URL?
        @Published var videoDurationText: String = "00:00"
        @Published var videoFrameCount: Int = 0
        @Published var videoFrameRate: Int = 0
        @Published var grayscaleImage: UIImage?
        @Published var videoWidth:Int = 0
        @Published  var videoHeight:Int = 0
        
        var videoTextures: [MTLTexture] = []
        var videoGrayTextures: [MTLTexture] = []
        
        var videoTrack: AVAssetTrack!
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var grayPipelineState: MTLComputePipelineState!
        init() {
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                
                let library = device.makeDefaultLibrary()
                let kernelFunction = library?.makeFunction(name: "grayscaleKernelSingleChannel")
                grayPipelineState = try! device.makeComputePipelineState(function: kernelFunction!)
        }
        
        func debugGrayResult() {
        }
        
        func grayImageOfFirstFrame(asset: AVAsset) throws {
                self.videoTextures.removeAll()
                let trackOutput = AVAssetReaderTrackOutput(track: self.videoTrack, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                let reader = try AVAssetReader(asset: asset)
                reader.add(trackOutput)
                reader.startReading()
                
                // 读取视频的第一个帧数据
                guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else{
                        print("------>>> read first frame from video failed");
                        return
                }
                
                // 将帧数据转换为灰度图
                guard let grayBuffer = computeGrayscaleAndConvertToImage(device:device, commandQueue:commandQueue, grayPipelineState:grayPipelineState,from: pixelBuffer) else{
                        print("------>>> convertToGrayscale failed");
                        return;
                }
                // 保存 grayBuffer 到文件
                saveGrayBufferToFile(buffer: grayBuffer, width: self.videoWidth, height: self.videoHeight)
                
                guard let grayImage =  grayBufferToUIImage(buffer: grayBuffer,width: self.videoWidth,height: self.videoHeight) else{
                        print("------>>> textureToUIImage failed");
                        return
                }
                
                DispatchQueue.main.async {
                        self.grayscaleImage = grayImage
                }
        }
        
        func parseVideoInfo() async throws {
                let frameRate = try await self.videoTrack.load(.nominalFrameRate)
                let timeRange = try await self.videoTrack.load(.timeRange)
                let frameCount = Int(frameRate * Float(timeRange.duration.value) / Float(timeRange.duration.timescale))
                
                DispatchQueue.main.async {
                        self.videoFrameCount = frameCount
                        self.videoFrameRate = Int(round(frameRate))
                }
        }
        
        func prepareVideoForGpu(url: URL) {
                Task {
                        do {
                                let asset = AVAsset(url: url)
                                let d = try await asset.load(.duration)
                                let duration = CMTimeGetSeconds(d)
                                if duration > constMaxVideoLen {
                                        print("视频时长不能超过20秒")
                                        return
                                }
                                
                                DispatchQueue.main.async {
                                        self.videoDurationText = formatTime(duration)
                                        self.videoURL = url
                                }
                                
                                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                                        print("No video track found")
                                        return
                                }
                                
                                self.videoTrack = videoTrack
                                
                                let videoSize = try await videoTrack.load(.naturalSize)
                                DispatchQueue.main.async {
                                        self.videoWidth = Int(videoSize.width)
                                        self.videoHeight = Int(videoSize.height)
                                }
                                
                                try await parseVideoInfo()
                                
                                try grayImageOfFirstFrame(asset: asset)
                                
                        } catch {
                                print("加载视频时长失败: \(error.localizedDescription)")
                        }
                }
        }
        
        func removeVideo() {
                videoURL = nil
                self.grayscaleImage = nil
        }
        
        func convertToGray() {
                
        }
        
        func reset() {
        }
}


