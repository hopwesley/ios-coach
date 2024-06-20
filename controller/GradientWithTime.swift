//
//  TimeGradient.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/18.
//


import Foundation
import UIKit
import AVFoundation

class GradientWithTime: ObservableObject {
        
        @Published var videoURL: URL?
        @Published var videoDurationText: String = "00:00"
        @Published var videoFrameCount: Int = 0
        @Published var videoFrameRate: Int = 0
        @Published var grayscaleImage: UIImage?
        @Published var gradientXImage: UIImage?
        @Published var gradientYImage: UIImage?
        @Published var gradientTImage: UIImage?
        @Published var videoWidth:Int = 0
        @Published  var videoHeight:Int = 0
        
        var videoTrack: AVAssetTrack!
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var grayPipelineState: MTLComputePipelineState!
        var spatialPipelineState: MTLComputePipelineState!
        var timePipelineState: MTLComputePipelineState!
        
        init() {
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                
                let library = device.makeDefaultLibrary()
                let grayFunction = library?.makeFunction(name: "grayscaleKernelSingleChannel")
                grayPipelineState = try! device.makeComputePipelineState(function: grayFunction!)
                let spatialFunction = library?.makeFunction(name: "sobelGradientAnswer")
                spatialPipelineState = try! device.makeComputePipelineState(function: spatialFunction!)
                let timeFunction = library?.makeFunction(name: "absDiffKernel")
                timePipelineState = try! device.makeComputePipelineState(function: timeFunction!)
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
                                
                                try gradientOfFrame(asset: asset)
                                
                        } catch {
                                print("加载视频时长失败: \(error.localizedDescription)")
                        }
                }
        }
        
        func gradientOfFrame(asset: AVAsset) throws{
                
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
                guard let grayFrameA = computeGrayscale(device:device, commandQueue:commandQueue, grayPipelineState:grayPipelineState,from: pixelBuffer) else{
                        print("------>>> convertToGrayscale failed");
                        return;
                }
                // 保存 grayBuffer 到文件
                saveRawDataToFile(fileName: "grayBufferA.json",
                                     buffer: grayFrameA,
                                     width: self.videoWidth,
                                     height: self.videoHeight,
                                     type: UInt8.self)
                guard let grayImage =  grayBufferToUIImage(buffer: grayFrameA,width: self.videoWidth,height: self.videoHeight) else{
                        print("------>>> textureToUIImage failed");
                        return
                }
                
                DispatchQueue.main.async {
                        self.grayscaleImage = grayImage
                }
                
                guard let (gradientX, gradientY) = spatialGradient(device:device,
                                                                   commandQueue: commandQueue,
                                                                   pipelineState:spatialPipelineState,
                                                                   grayBuffer: grayFrameA,
                                                                   width: self.videoWidth,
                                                                   height: self.videoHeight)else{
                        print("------>>> spatialGradient failed");
                        return;
                }
                
                saveRawDataToFile(fileName: "gradientXBuffer.json",
                                     buffer: gradientX,
                                     width: self.videoWidth,
                                     height: self.videoHeight,
                                     type: Int16.self)
                guard let convertedGradientX = convertInt16ToUInt8(buffer: gradientX, width: self.videoWidth, height: self.videoHeight)else{
                        print("------>>> convertInt16ToUInt8 for gradientX failed");
                        return;
                }
                if let gradientXImage = grayBufferToUIImage(buffer: convertedGradientX,
                                                            width: self.videoWidth,
                                                            height: self.videoHeight){
                        DispatchQueue.main.async {
                                self.gradientXImage = gradientXImage
                        }
                }
                
                saveRawDataToFile(fileName: "gradientYBuffer.json",
                                     buffer: gradientY,
                                     width: self.videoWidth,
                                     height: self.videoHeight,
                                     type: Int16.self)
                
                guard let convertedGradientY = convertInt16ToUInt8(buffer: gradientY, width: self.videoWidth, height: self.videoHeight)else{
                        print("------>>> convertInt16ToUInt8 for gradientX failed");
                        return;
                }
                
                if let gradientYImage = grayBufferToUIImage(buffer: convertedGradientY,width: self.videoWidth,height: self.videoHeight){
                        DispatchQueue.main.async {
                                self.gradientYImage = gradientYImage
                        }
                }
                
                // 读取视频的第二个帧数据
                guard let sampleBufferB = trackOutput.copyNextSampleBuffer(),
                      let pixelBufferB = CMSampleBufferGetImageBuffer(sampleBufferB) else{
                        print("------>>> read second frame from video failed")
                        return
                }
                
                guard let grayFrameB = computeGrayscale(device:device, commandQueue:commandQueue, grayPipelineState:grayPipelineState,from: pixelBufferB) else{
                        print("------>>> convertToGrayscale failed");
                        return;
                }
                
                guard let gradientT = timeGradient(device: device, commandQueue: commandQueue, pipelineState: timePipelineState, grayFrameA: grayFrameA, grayFrameB: grayFrameB, width: self.videoWidth, height: self.videoHeight) else{
                        print("------>>> timeGradient for gradientX failed");
                        return;
                }
                
                saveRawDataToFile(fileName: "gradientTBuffer.json",
                                     buffer: gradientT,
                                     width: self.videoWidth,
                                     height: self.videoHeight,
                                     type: UInt8.self)
         
                if let gradientTImage = grayBufferToUIImage(buffer: gradientT,width: self.videoWidth,height: self.videoHeight){
                        DispatchQueue.main.async {
                                self.gradientTImage = gradientTImage
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
