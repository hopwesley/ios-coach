import SwiftUI
import AVKit
import AVFoundation
import PhotosUI

struct ContentView: View {
        @State private var errorInfo = ""
        @State private var processingTime: Double? = nil
        @StateObject private var videoCtlA = VideoAlignment()
        @StateObject private var videoCtlB = VideoAlignment()
        @State private var sliderValue: Double = 20000
        @State private var maxSliderValue: Double = 100.0
        @State private var isProcessing = false
        @State private var showCompareView = false
        
        
        var body: some View {
                NavigationStack {
                        ZStack {
                                ScrollView {
                                        VStack {
                                                VideoPickerView(videoController: videoCtlA)
                                                VideoPickerView(videoController: videoCtlB)
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
                        }.navigationDestination(isPresented: $showCompareView) {
                                CompareView(videoCtlA: videoCtlA, videoCtlB: videoCtlB, processingTime: processingTime)
                        }
                }
        }
        
        func processingTimeAlign(maxFrame: Int) {
                guard videoCtlA.videoURL != nil, videoCtlB.videoURL != nil else {
                        print("需要两个视频进行比较")
                        return
                }
                
                let startTime = Date()
                var histogramOfA: (MTLBuffer, Int)? = nil
                var histogramOfB: (MTLBuffer, Int)? = nil
                let group = DispatchGroup()
                
                DispatchQueue.main.async {
                        self.isProcessing = true
                }
                
                group.enter()
                videoCtlA.AlignVideo { result in
                        switch result {
                        case .success(let buffer):
                                histogramOfA = buffer
                        case .failure(let error):
                                self.errorInfo = "无法对齐视频A: \(error.localizedDescription)"
                        }
                        group.leave()
                }
                group.enter()
                videoCtlB.AlignVideo { result in
                        switch result {
                        case .success(let buffer):
                                histogramOfB = buffer
                        case .failure(let error):
                                self.errorInfo = "无法对齐视频B: \(error.localizedDescription)"
                        }
                        group.leave()
                }
                group.notify(queue: .global()) {
                        guard let A = histogramOfA, let B = histogramOfB else {
                                self.errorInfo = "解析帧梯度失败"
                                return
                        }
                        let (bufferA, countA) = A
                        let (bufferB, countB) = B
                        
                        guard let (offsetA, offsetB) = findBestAlignOffset(histoA: bufferA, countA: countA,
                                                                           histoB: bufferB, countB: countB, seqLen: maxFrame) else {
                                return
                        }
                        
                        print("aIdx=\(offsetA) bIdx=\(offsetB)")
                        let endTime = Date()
                        let executionTime = endTime.timeIntervalSince(startTime)
                        Task {
                                do {
                                        async let resultA: () = videoCtlA.cipherVideo(offset: offsetA, len: maxFrame)
                                        async let resultB: () =  videoCtlB.cipherVideo(offset: offsetB, len: maxFrame)
                                        
                                        try await resultA
                                        try await resultB
                                } catch let err {
                                        DispatchQueue.main.async {
                                                self.errorInfo = err.localizedDescription
                                        }
                                }
                        }
                        
                        DispatchQueue.main.async {
                                self.processingTime = executionTime
                                self.isProcessing = false
                                self.showCompareView = true // 设置为true以显示CompareView
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
                                        .frame(height: 400)
                                        .background(Color.black)
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
                                                .frame(height: 200)
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


struct CompareView: View {
        @ObservedObject var videoCtlA: VideoAlignment
        @ObservedObject var videoCtlB: VideoAlignment
        var processingTime: Double?
        var comparedUrl: URL?
        
        var body: some View {
                VStack(spacing: 20) {
                        if let time = processingTime {
                                Text("处理时间: \(time, specifier: "%.2f") 秒")
                                        .padding(.top, 20) // Adjust top padding
                        }
                        
                        if let urlA = videoCtlA.cipheredVideoUrl, let urlB = videoCtlB.cipheredVideoUrl {
                                HStack(spacing: 20) {
                                        VideoPlayer(player: AVPlayer(url: urlA))
                                                .frame(height: 200)
                                                .background(Color.black)
                                        
                                        VideoPlayer(player: AVPlayer(url: urlB))
                                                .frame(height: 200)
                                                .background(Color.black)
                                }
                                
                                Button(action: {
                                        compareVideo()
                                }) {
                                        Text("对比视频")
                                                .frame(width: 160, height: 80) // Adjust button size
                                                .background(Color.gray)
                                                .foregroundColor(.white)
                                                .cornerRadius(10)
                                }
                                .padding(.top, 20) // Adjust top padding
                                
                                if let comparedUrl = comparedUrl {
                                        VideoPlayer(player: AVPlayer(url: comparedUrl))
                                                .frame(height: 200)
                                                .background(Color.black)
                                }
                        }
                }
                .padding(20) // Add padding around the entire content
                .background(Color.white) // Add a white background
                .cornerRadius(10) // Apply corner radius to the entire view
                .shadow(radius: 5) // Add shadow for better visibility
        }
        
        func compareVideo() {
                // Implement video comparison logic here
                // For example, set comparedUrl to the comparison result URL
                // You would need to implement the logic based on your requirements
        }
}
