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
        @Published var videoFrameRate: Int = 0
        var videoTextures: [MTLTexture] = []
        var videoGrayTextures: [MTLTexture] = []
        var device: MTLDevice? = MTLCreateSystemDefaultDevice()
        var grayscalePipelineState:MTLComputePipelineState!
        var videoTrack:AVAssetTrack!
        var textureDesc:MTLTextureDescriptor!
        
        init() {
                device = MTLCreateSystemDefaultDevice()
                setupGrayscalePipeline()
        }
        
        private func setupGrayscalePipeline() {
                guard let device = device else { return }
                
                do {
                        let library = try device.makeDefaultLibrary(bundle: Bundle.main)
                        let kernelFunction = library.makeFunction(name: "grayscaleKernel")
                        grayscalePipelineState = try device.makeComputePipelineState(function: kernelFunction!)
                } catch {
                        print("Failed to create compute pipeline state: \(error)")
                }
        }
        
        func convertToGrayTexture() {
                guard let commandQueue = device!.makeCommandQueue() else { return }
                let commandBuffer = commandQueue.makeCommandBuffer()
                let computeEncoder = commandBuffer?.makeComputeCommandEncoder()
                computeEncoder?.setComputePipelineState(grayscalePipelineState)
                var idx = 0
                for texture in videoTextures {
                        if let outputTexture = device!.makeTexture(descriptor: self.textureDesc) {
                                computeEncoder?.setTexture(texture, index: 0)  // 输入纹理
                                computeEncoder?.setTexture(outputTexture, index: 1)  // 输出纹理
                                
                                let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
                                let threadGroups = MTLSize(
                                        width: (texture.width + threadGroupSize.width - 1) / threadGroupSize.width,
                                        height: (texture.height + threadGroupSize.height - 1) / threadGroupSize.height,
                                        depth: 1
                                )
                                computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                                videoGrayTextures.append(outputTexture)
                                idx+=1
                                print("------>>> gray texture created:", idx)
                        }
                }
                
                computeEncoder?.endEncoding()
                commandBuffer?.commit()
                //                commandBuffer?.waitUntilCompleted()
                commandBuffer?.addCompletedHandler { buffer in
                        print("GPU operations completed")
                        if buffer.status == .completed {
                                print("GPU operations completed successfully")
                        } else if buffer.status == .error {
                                if let error = buffer.error {
                                        print("GPU operations failed: \(error.localizedDescription)")
                                }
                        }
                }
                
                videoTextures = []
        }
        
        
        func parseTextFromVideo(asset:AVAsset) throws{
                
                self.videoTextures.removeAll()
                let trackOutput = AVAssetReaderTrackOutput(track: self.videoTrack, outputSettings: [
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
        
        func createTextureDescriptorForVideo() async throws-> MTLTextureDescriptor {
                
                let naturalSize = try await self.videoTrack.load(.naturalSize)
                let width = Int(naturalSize.width)
                let height = Int(naturalSize.height)
                print("------>>>width:",width," height:",height)
                let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: width,
                        height: height,
                        mipmapped: false
                )
                textureDescriptor.usage = [.shaderRead, .shaderWrite]
                textureDescriptor.storageMode = .private
                
                return textureDescriptor
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
                                
                                self.textureDesc = try await createTextureDescriptorForVideo()
                                
                                try await parseVideoInfo()
                                
                                try parseTextFromVideo(asset: asset)
                                
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
                convertToGrayTexture()
        }
        func reset() {
        }
}
