import SwiftUI
import MetalKit
import AVKit
import PhotosUI

let constMaxVideoLen = 20.0
struct ContentView: View {
        @StateObject private var viewModelVideo1 = VideoProcessingViewModel()
        @StateObject private var viewModelVideo2 = VideoProcessingViewModel()
        @State private var showImagePicker1 = false
        @State private var showImagePicker2 = false
        var body: some View {
                VStack {
                        // 第一行：统计信息
                        VStack(alignment: .leading) {
                                Text("统计信息")
                                        .font(.headline)
                                HStack {
                                        Text("视频1时长: \(viewModelVideo1.videoDurationText)")
                                        Spacer()
                                        Text("视频2时长: \(viewModelVideo2.videoDurationText)")
                                }
                                HStack {
                                        Text("视频1帧数: \(viewModelVideo1.videoFrameCount)")
                                        Spacer()
                                        Text("视频2帧数: \(viewModelVideo2.videoFrameCount)")
                                }
                                HStack {
                                        Text("视频1帧速率: \(viewModelVideo1.videoFrameRate)")
                                        Spacer()
                                        Text("视频2帧速率: \(viewModelVideo2.videoFrameRate)")
                                }
                        }
                        .padding()
                        .border(Color.gray, width: 1)
                        
                        VStack {
                                ZStack {
                                        if let videoURL = viewModelVideo1.videoURL {
                                                VideoPlayer(player: AVPlayer(url: videoURL))
                                                        .frame(height: 200)
                                                Button(action: {
                                                        viewModelVideo1.removeVideo()
                                                }) {
                                                        Image(systemName: "trash")
                                                                .foregroundColor(.red)
                                                                .padding()
                                                                .background(Color.white)
                                                                .cornerRadius(20)
                                                }
                                                .offset(x: 140, y: -90)
                                        } else {
                                                VStack {
                                                        Button(action: {
                                                                showImagePicker1 = true
                                                        }) {
                                                                Image(systemName: "plus")
                                                                        .font(.largeTitle)
                                                                        .padding()
                                                        }
                                                        Text("点击加载视频(最长20s)")
                                                                .foregroundColor(.gray)
                                                }
                                                .frame(height: 200)
                                                .border(Color.gray, width: 1)
                                        }
                                }
                        }
                        .sheet(isPresented: $showImagePicker1) {
                                PHPickerViewController.View(videoPicked: { url in
                                        showImagePicker1 = false
                                        viewModelVideo1.prepareVideoForGpu(url: url)
                                })
                        }
                        
                        // 第三行：加载第二个视频
                        VStack {
                                ZStack {
                                        if let videoURL = viewModelVideo2.videoURL {
                                                VideoPlayer(player: AVPlayer(url: videoURL))
                                                        .frame(height: 200)
                                                Button(action: {
                                                        viewModelVideo2.removeVideo()
                                                }) {
                                                        Image(systemName: "trash")
                                                                .foregroundColor(.red)
                                                                .padding()
                                                                .background(Color.white)
                                                                .cornerRadius(20)
                                                }
                                                .offset(x: 140, y: -90)
                                        } else {
                                                VStack {
                                                        Button(action: {
                                                                showImagePicker2 = true
                                                        }) {
                                                                Image(systemName: "plus")
                                                                        .font(.largeTitle)
                                                                        .padding()
                                                        }
                                                        Text("点击加载视频(最长20s)")
                                                                .foregroundColor(.gray)
                                                }
                                                .frame(height: 200)
                                                .border(Color.gray, width: 1)
                                        }
                                }
                        }
                        .sheet(isPresented: $showImagePicker2) {
                                PHPickerViewController.View(videoPicked: { url in
                                        showImagePicker2 = false
                                        viewModelVideo2.prepareVideoForGpu(url: url)
                                })
                        }
                        
                        HStack {
                                Button(action: {
                                        viewModelVideo1.convertToGray()
                                        viewModelVideo2.convertToGray()
                                }) {
                                        Text("转为灰度")
                                }
                                Button(action: {
                                        
                                }) {
                                        Text("开始对齐")
                                }
                                Button(action: {
                                        
                                }) {
                                        Text("开始对比")
                                }
                                Button(action: {
                                        
                                }) {
                                        Text("重新加载")
                                }
                        }
                        .padding()
                        
                        VStack {
                                Text("处理结果")
                                        .font(.headline)
                        }
                        .padding()
                        .border(Color.gray, width: 1)
                }
                .padding()
        }
}

class VideoProcessingViewModel: ObservableObject {
        @Published var videoURL: URL?
        @Published var videoDurationText: String = "00:00"
        @Published var videoFrameCount: Int = 0
        @Published var videoFrameRate: Float = 0.0
        var videoTextures: [MTLTexture] = []
        var device: MTLDevice? = MTLCreateSystemDefaultDevice()
        
        func prepareTextureForVideoFrame(asset:AVAsset,videoTrack:AVAssetTrack) throws{
                
                self.videoTextures.removeAll()
                let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                let reader = try AVAssetReader(asset: asset)
                reader.add(trackOutput)
                reader.startReading()
                var idx = 0
                while let sampleBuffer = trackOutput.copyNextSampleBuffer()  {
                        guard let texture = try createTextureFromBuffer(sampleBuffer: sampleBuffer) else{
                                continue
                        }
                        idx+=1
                        print("------>>>new texture created:", idx)
                        self.videoTextures.append(texture)
                }
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
                                
                                
                                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                                        print("No video track found")
                                        return
                                }
                                
                                let frameRate =  try await videoTrack.load(.nominalFrameRate)
                                let timeRange = try await videoTrack.load(.timeRange)
                                let frameCount = Int(frameRate * Float(timeRange.duration.value) / Float(timeRange.duration.timescale))
                                
                                DispatchQueue.main.async {
                                        self.videoURL = url
                                        self.videoDurationText = self.formatTime(duration)
                                        self.videoFrameCount = frameCount
                                        self.videoFrameRate = frameRate
                                }
                                
                                try prepareTextureForVideoFrame(asset: asset, videoTrack: videoTrack)
                                
                        }catch{
                                print("加载视频时长失败: \(error.localizedDescription)")
                        }
                }
        }
        
        private func createTextureFromBuffer(sampleBuffer: CMSampleBuffer) throws -> MTLTexture? {
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else{
                        return nil
                }
                
                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                let context = CIContext(mtlDevice: device!)
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer), mipmapped: false)
                textureDescriptor.usage = .shaderRead
                textureDescriptor.storageMode = .private
                
                guard let texture = device!.makeTexture(descriptor: textureDescriptor) else {
                        print("Unable to create texture")
                        return nil
                }
                
                context.render(ciImage, to: texture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                return texture
        }
        
        func formatTime(_ seconds: Double) -> String {
                let minutes = Int(seconds) / 60
                let seconds = Int(seconds) % 60
                return String(format: "%02d:%02d", minutes, seconds)
        }
        
        func removeVideo() {
                videoURL = nil
        }
        
        func convertToGray() {
        }
        func reset() {
        }
}
