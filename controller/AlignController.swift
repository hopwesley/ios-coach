//
//  AlignController.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/21.
//

import Foundation
import AVFoundation
class AlignController: ObservableObject {
        
        @Published var videoURL: URL?
        @Published var videoInfo:String?
        
        var videoWidth:Double = 0
        var videoHeight:Double = 0
        var videoTrack: AVAssetTrack!
        
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var alignPipelineState: MTLComputePipelineState!
        
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
                        throw VideoParsingError.VideoTooLong
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
        }
        
        func histogramOfAllFrame()->MTLBuffer?{
                return nil
        }
}
