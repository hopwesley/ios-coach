//
//  SpatialGradient.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/17.
//

import Foundation
import UIKit
import AVFoundation

class SpatialGradient: ObservableObject {
        
        @Published var videoURL: URL?
        @Published var videoDurationText: String = "00:00"
        @Published var videoFrameCount: Int = 0
        @Published var videoFrameRate: Int = 0
        @Published var grayscaleImage: UIImage?
        @Published var gradientXImage: UIImage?
        @Published var gradientYImage: UIImage?
        @Published var videoWidth:Int = 0
        @Published  var videoHeight:Int = 0
        
        var videoTrack: AVAssetTrack!
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var grayPipelineState: MTLComputePipelineState!
        var spatialPipelineState: MTLComputePipelineState!
        
        init() {
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                
                let library = device.makeDefaultLibrary()
                let grayFunction = library?.makeFunction(name: "grayscaleKernel")
                grayPipelineState = try! device.makeComputePipelineState(function: grayFunction!)
                let spatialFunction = library?.makeFunction(name: "spatialGradientKernel")
                spatialPipelineState = try! device.makeComputePipelineState(function: spatialFunction!)
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
                                
                                try spatialFirstFrame(asset: asset)
                                
                        } catch {
                                print("加载视频时长失败: \(error.localizedDescription)")
                        }
                }
        }
        
        func spatialFirstFrame(asset: AVAsset) throws{
                
                let trackOutput = AVAssetReaderTrackOutput(track: self.videoTrack, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                let reader = try AVAssetReader(asset: asset)
                reader.add(trackOutput)
                reader.startReading()
                
                // 读取视频的第一个帧数据
                guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else{
                        print("------>>> read first frame from video failed")
                        return
                }
                // 将帧数据转换为灰度图
                guard let grayImageTexture = convertToGrayscale(device:device, commandQueue:commandQueue, computePipelineState:grayPipelineState,from: pixelBuffer) else{
                        print("------>>> convertToGrayscale failed");
                        return;
                }
                
                guard let grayImage =  textureToUIImage(texture: grayImageTexture) else{
                        print("------>>> textureToUIImage failed");
                        return
                }
                
                DispatchQueue.main.async {
                        self.grayscaleImage = grayImage
                }
                
                guard let (gradientX, gradientY) = computeSpatialGradient(device:device,commandQueue: commandQueue,gradientPipelineState:spatialPipelineState, for: grayImageTexture)else{
                        print("------>>> computeSpatialGradient failed");
                        return;
                }
                //                print("Gradient X: \(gradientX)")
                //                print("Gradient Y: \(gradientY)")
                
//                let normalizedGradientX = normalizeGradient(gradientX, width: grayImageTexture.width, height: grayImageTexture.height)
//                let normalizedGradientY = normalizeGradient(gradientY, width: grayImageTexture.width, height: grayImageTexture.height)
//                
                if let gradientXTexture = createTextureFromGradient(device: device, width: grayImageTexture.width, height: grayImageTexture.height, gradient: gradientX),
                   let gradientXImage = textureToUIImage(texture: gradientXTexture) {
                        DispatchQueue.main.async {
                                self.gradientXImage = gradientXImage
                        }
                }
                
                if let gradientYTexture = createTextureFromGradient(device: device, width: grayImageTexture.width, height: grayImageTexture.height, gradient: gradientY),
                   let gradientYImage = textureToUIImage(texture: gradientYTexture) {
                        DispatchQueue.main.async {
                                self.gradientYImage = gradientYImage
                        }
                }
        }
        
        func removeVideo() {
                videoURL = nil
                self.grayscaleImage = nil
                self.gradientXImage = nil
                self.gradientYImage = nil
        }
        
        func convertToGray() {
                
        }
        
        func reset() {
        }
}
