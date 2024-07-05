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
                                        
                                        HStack{
                                                
                                                Button(action: {
                                                        processingTimeAlign(maxFrame: Int(sliderValue))
                                                }) {
                                                        Text("自动对齐")
                                                }
                                                .frame(width: 160, height: 80)
                                                .background(Color.gray)
                                                
                                                Button(action: {
                                                        
                                                }) {
                                                        Text("手动对齐")
                                                }
                                                .frame(width: 160, height: 80)
                                                .background(Color.gray)
                                        }
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
                                CompareView(urlA: videoCtlA.cipheredVideoUrl, urlB: videoCtlB.cipheredVideoUrl, alignTime: processingTime)
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
                        
                        guard let (offsetA, offsetB, seqLen) = findBestAlignOffset(histoA: bufferA, countA: countA,
                                                                                   histoB: bufferB, countB: countB, seqLen: maxFrame) else {
                                return
                        }
                        
                        print("aIdx=\(offsetA) bIdx=\(offsetB)")
                        let endTime = Date()
                        let executionTime = endTime.timeIntervalSince(startTime)
                        Task {
                                do {
                                        async let resultA: () = videoCtlA.cipherVideo(buffer:bufferA, offset: offsetA, len: seqLen)
                                        async let resultB: () = videoCtlB.cipherVideo(buffer:bufferB,offset: offsetB, len: seqLen)
                                        
                                        try await resultA
                                        try await resultB
                                        DispatchQueue.main.async {// 设置为true以显示CompareView
                                                self.processingTime = executionTime
                                                self.isProcessing = false
                                                self.showCompareView = true 
                                        }
                                } catch let err {
                                        DispatchQueue.main.async {
                                                self.errorInfo = err.localizedDescription
                                        }
                                }
                        }
                }
        }
}
