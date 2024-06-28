import SwiftUI
import AVFoundation
import _AVKit_SwiftUI
import PhotosUI

struct ContentView: View {
        @State private var errorInfo = ""
        @State private var processingTime: Double? = nil
        @StateObject private var videoCtlA = VideoAlignment()
        @StateObject private var videoCtlB = VideoAlignment()
        
        @State private var sliderValue: Double = 20000
        @State private var maxSliderValue: Double = 100.0
        @State private var isProcessing = false
        
        var body: some View {
                ZStack {
                        ScrollView {
                                VStack {
                                        VideoPickerView(videoController: videoCtlA)
                                        VideoPickerView(videoController: videoCtlB)
                                }
                                VStack {
                                        Button(action: {
                                                videoCtlA.DebugAlignVideo()
                                        }) {
                                                Text("Test")
                                        }
                                        .frame(width: 160, height: 80)
                                        .background(Color.gray)
                                        
                                        Text(errorInfo)
                                        if let time = processingTime {
                                                Text("Processing time: \(time, specifier: "%.2f") seconds")
                                        }
                                }
                                VStack {
                                        if let aCount = videoCtlA.FrameCount, let bCount = videoCtlB.FrameCount {
                                                let msv = Double(min(aCount, bCount))
                                                Text("对齐帧数: \(Int(sliderValue))")
                                                HStack {
                                                        Text("1")
                                                        Slider(value: $sliderValue, in: 1...Double(msv))
                                                        Text("\(Int(msv))")
                                                }
                                                .padding()
                                                .onAppear {
                                                        self.maxSliderValue = msv
                                                        if Int(sliderValue) > Int(maxSliderValue) {
                                                                sliderValue = Double(maxSliderValue)
                                                        }
                                                }
                                        }
                                }
                                
                                Button(action: {
                                        processingTimeAlign(maxFrame: Int(sliderValue))
                                }) {
                                        Text("对齐")
                                }
                                .frame(width: 160, height: 80)
                                .background(Color.gray)
                        }
                        .allowsHitTesting(!isProcessing)
                        if isProcessing {
                                // Waiting view
                                VStack {
                                        Text("正在处理，请稍候...")
                                                .padding()
                                                .background(Color.black.opacity(0.75))
                                                .cornerRadius(10)
                                                .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.5).edgesIgnoringSafeArea(.all))
                        }
                }
        }
        
        func processingTimeAlign(maxFrame: Int) {
                guard videoCtlA.videoURL != nil, videoCtlB.videoURL != nil else {
                        print("need 2 video to be compared")
                        return
                }
                
                let startTime = Date()
                
                var histogramOfA: (MTLBuffer, Int)? = nil
                var histogramOfB: (MTLBuffer, Int)? = nil
                let group = DispatchGroup()
                
                // Show waiting view
                DispatchQueue.main.async {
                        self.isProcessing = true
                }
                
                group.enter()
                videoCtlA.AlignVideo { result in
                        switch result {
                        case .success(let buffer):
                                histogramOfA = buffer
                        case .failure(let error):
                                self.errorInfo = "Failed to align video A: \(error.localizedDescription)"
                        }
                        group.leave()
                }
                group.enter()
                videoCtlB.AlignVideo { result in
                        switch result {
                        case .success(let buffer):
                                histogramOfB = buffer
                        case .failure(let error):
                                self.errorInfo = "Failed to align video B: \(error.localizedDescription)"
                        }
                        group.leave()
                }
                group.notify(queue: .global()) {
                        
                        guard let A = histogramOfA, let B = histogramOfB else {
                                self.errorInfo = "parse frame gradient failed"
                                return
                        }
                        let (bufferA, countA) = A
                        let (bufferB, countB) = B
                        
                        guard let (offsetA, offsetB) = findBestAlignOffset(histoA: bufferA,countA: countA,
                                                                           histoB: bufferB,countB: countB, seqLen: maxFrame) else {
                                return
                        }
                        
                        videoCihper(url: videoCtlA.videoURL!, offset: offsetA)
                        videoCihper(url: videoCtlB.videoURL!, offset: offsetB)
                        let endTime = Date()  // Record the end time
                        let executionTime = endTime.timeIntervalSince(startTime)
                        DispatchQueue.main.async {
                                self.processingTime = executionTime  // Update the processing time
                                self.isProcessing = false  // Hide waiting view
                        }
                }
        }
}

struct VideoPickerView: View {
        @ObservedObject var videoController: VideoAlignment
        @State private var showVideoPicker = false
        
        var body: some View {
                VStack {
                        if let videoUrl = videoController.videoURL {
                                VideoPlayer(player: AVPlayer(url: videoUrl))
                                        .frame(height: 400) // 固定高度
                                        .background(Color.black) // 设置背景颜色以确保视频显示区域
                                Button(action: {
                                        videoController.removeVideo()
                                }) {
                                        Image(systemName: "trash")
                                                .foregroundColor(.red)
                                                .padding()
                                                .background(Color.white)
                                                .cornerRadius(20)
                                }
                                if let info = videoController.videoInfo {
                                        Text(info)
                                }
                        } else {
                                Button(action: {
                                        showVideoPicker = true
                                }) {
                                        Image(systemName: "plus")
                                                .font(.largeTitle)
                                                .padding()
                                                .frame(height: 200) // 固定高度
                                                .frame(maxWidth: .infinity)
                                                .background(Color.gray.opacity(0.3))
                                                .cornerRadius(10)
                                }
                        }
                }
                .sheet(isPresented: $showVideoPicker) {
                        PHPickerViewController.View(videoPicked: { url in
                                showVideoPicker = false
                                videoController.prepareVideoInBackground(url: url)
                        })
                }
        }
}
