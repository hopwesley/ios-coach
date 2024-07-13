import SwiftUI
import AVFoundation
import Combine

let frameInterval = 0.1 // 每0.1秒一个关键帧

struct ManualAlignView: View {
        var urlA: URL
        var urlB: URL
        
        @State private var trimedUrlA: URL?
        @State private var trimedUrlB: URL?
        
        @State private var startTimeA: Double = 0
        @State private var endTimeA: Double = 10
        @State private var startTimeB: Double = 0
        @State private var endTimeB: Double = 10
        
        @State private var videoLengthA: Double = 10
        @State private var videoLengthB: Double = 10
        
        @State private var thumbnailsA: [UIImage] = []
        @State private var thumbnailsB: [UIImage] = []
        
        @State private var selectedStartIndexA: Int = 0
        @State private var selectedEndIndexA: Int?
        @State private var selectedStartIndexB: Int = 0
        @State private var selectedEndIndexB: Int?
        
        @State private var frameCountA: Int = 0
        @State private var frameCountB: Int = 0
        
        @State private var scrollViewProxyA: ScrollViewProxy?
        @State private var scrollViewProxyB: ScrollViewProxy?
        
        @State private var showAlert = false
        @State private var alertMessage = ""
        @State private var isProcessing = false
        @State private var showCompareView = false
        
        init(urlA: URL, urlB: URL) {
                self.urlA = urlA
                self.urlB = urlB
        }
        
        var body: some View {
                NavigationStack {
                        ZStack{
                                VStack {
                                        ScrollView {
                                                VStack {
                                                        // Video A
                                                        videoThumbnailsView(thumbnails: $thumbnailsA, selectedStartIndex: $selectedStartIndexA, selectedEndIndex: $selectedEndIndexA, scrollViewProxy: $scrollViewProxyA)
                                                        
                                                        videoControlView(startTime: $startTimeA, endTime: $endTimeA, videoLength: videoLengthA, selectedStartIndex: $selectedStartIndexA, selectedEndIndex: $selectedEndIndexA, thumbnails: thumbnailsA, frameCount: $frameCountA, isA: true)
                                                        
                                                        Divider().padding()
                                                        
                                                        // Video B
                                                        videoThumbnailsView(thumbnails: $thumbnailsB, selectedStartIndex: $selectedStartIndexB, selectedEndIndex: $selectedEndIndexB, scrollViewProxy: $scrollViewProxyB)
                                                        
                                                        videoControlView(startTime: $startTimeB, endTime: $endTimeB, videoLength: videoLengthB, selectedStartIndex: $selectedStartIndexB, selectedEndIndex: $selectedEndIndexB, thumbnails: thumbnailsB, frameCount: $frameCountB, isA: false)
                                                        
                                                        saveButton
                                                }
                                                .padding()
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
                                }
                                .onAppear {
                                        Task {
                                                await loadVideoData()
                                        }
                                }
                        }.navigationDestination(isPresented: $showCompareView) {
                                CompareView(urlA: trimedUrlA, urlB: trimedUrlB, alignTime:0)
                        }
                }
        }
        
        private func videoThumbnailsView(thumbnails: Binding<[UIImage]>, selectedStartIndex: Binding<Int>, selectedEndIndex: Binding<Int?>, scrollViewProxy: Binding<ScrollViewProxy?>) -> some View {
                ScrollView(.horizontal, showsIndicators: true) {
                        ScrollViewReader { proxy in
                                HStack {
                                        ForEach(thumbnails.wrappedValue.indices, id: \.self) { index in
                                                ZStack {
                                                        if index == selectedStartIndex.wrappedValue {
                                                                Rectangle()
                                                                        .fill(Color.green)
                                                                        .frame(width: 140, height: 220)
                                                        } else if index == selectedEndIndex.wrappedValue {
                                                                Rectangle()
                                                                        .fill(Color.red)
                                                                        .frame(width: 140, height: 220)
                                                        }
                                                        Image(uiImage: thumbnails.wrappedValue[index])
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fit)
                                                                .frame(height: 200)
                                                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                                }
                                                .padding(5)
                                                .border(Color.black, width: 1)
                                                .id(index)
                                        }
                                }
                                .padding()
                                .onAppear {
                                        scrollViewProxy.wrappedValue = proxy
                                }
                        }
                }
                .scrollIndicators(.visible)
        }
        
        private func videoControlView(startTime: Binding<Double>, endTime: Binding<Double>, videoLength: Double, selectedStartIndex: Binding<Int>, selectedEndIndex: Binding<Int?>, thumbnails: [UIImage], frameCount: Binding<Int>, isA: Bool) -> some View {
                VStack {
                        Text("Frames in selection: \(frameCount.wrappedValue)")
                        
                        Text("Start Time \(isA ? "A" : "B"): \(startTime.wrappedValue, specifier: "%.2f") seconds")
                        Slider(value: startTime, in: 0...videoLength, step: frameInterval)
                                .onChange(of: startTime.wrappedValue) { newValue in
                                        if startTime.wrappedValue >= endTime.wrappedValue {
                                                startTime.wrappedValue = endTime.wrappedValue - frameInterval
                                        }
                                        updateSelectedIndex(for: startTime.wrappedValue, videoLength: videoLength, thumbnails: thumbnails, isStart: true, isA: isA)
                                        scrollToSelectedIndex(selectedStartIndex.wrappedValue, isA: isA)
                                }
                        
                        Text("End Time \(isA ? "A" : "B"): \(endTime.wrappedValue, specifier: "%.2f") seconds")
                        Slider(value: endTime, in: 0...videoLength, step: frameInterval)
                                .onChange(of: endTime.wrappedValue) { newValue in
                                        if endTime.wrappedValue <= startTime.wrappedValue {
                                                endTime.wrappedValue = startTime.wrappedValue + frameInterval
                                        }
                                        updateSelectedIndex(for: endTime.wrappedValue, videoLength: videoLength, thumbnails: thumbnails, isStart: false, isA: isA)
                                        scrollToSelectedIndex(selectedEndIndex.wrappedValue, isA: isA)
                                }
                }
        }
        
        private var saveButton: some View {
                Button("Save") {
                        if frameCountA != frameCountB {
                                alertMessage = "对比度视频长度必须相同"
                                showAlert = true
                        } else {
                                prepareVideoToCompare()
                        }
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .alert(isPresented: $showAlert) {
                        Alert(title: Text("错误"), message: Text(alertMessage), dismissButton: .default(Text("确定")))
                }
        }
        
        private func prepareVideoToCompare(){
                DispatchQueue.main.async {
                        self.isProcessing = true
                }
                Task{
                        do {
                                async let trimedUrlA = trimVideoByTime(videoURL: urlA, sTime: startTimeA, eTime: endTimeA)
                                async let trimedUrlB = trimVideoByTime(videoURL: urlB, sTime: startTimeB, eTime: endTimeB)
                                
                                let (resultA, resultB) = try await (trimedUrlA, trimedUrlB)
                                DispatchQueue.main.async {
                                        self.isProcessing = false
                                        self.trimedUrlA = resultA
                                        self.trimedUrlB = resultB
                                        self.showCompareView = true
                                }
                        } catch let err {
                                DispatchQueue.main.async {
                                        alertMessage = err.localizedDescription
                                        showAlert = true
                                }
                        }
                }
        }
        
        private func updateSelectedIndex(for time: Double, videoLength: Double, thumbnails: [UIImage], isStart: Bool, isA: Bool) {
                let index = Int((time / videoLength) * Double(thumbnails.count))
                if isA {
                        if isStart {
                                selectedStartIndexA = index
                        } else {
                                selectedEndIndexA = index
                        }
                        updateFrameCountA()
                } else {
                        if isStart {
                                selectedStartIndexB = index
                        } else {
                                selectedEndIndexB = index
                        }
                        updateFrameCountB()
                }
        }
        
        private func updateFrameCountA() {
                if let endIndex = selectedEndIndexA {
                        frameCountA = endIndex - selectedStartIndexA + 1
                } else {
                        frameCountA = 0
                }
        }
        
        private func updateFrameCountB() {
                if let endIndex = selectedEndIndexB {
                        frameCountB = endIndex - selectedStartIndexB + 1
                } else {
                        frameCountB = 0
                }
        }
        
        private func scrollToSelectedIndex(_ index: Int?, isA: Bool) {
                guard let index = index else { return }
                if isA, let proxy = scrollViewProxyA {
                        proxy.scrollTo(index, anchor: .center)
                } else if !isA, let proxy = scrollViewProxyB {
                        proxy.scrollTo(index, anchor: .center)
                }
        }
        
        @MainActor
        private func loadVideoData() async {
                await loadVideoLength(for: urlA) { length in
                        videoLengthA = length
                        endTimeA = length
                }
                await extractThumbnails(from: urlA) { images in
                        thumbnailsA = images
                        selectedEndIndexA = images.count - 1 // 设置红色为最后一帧
                        updateFrameCountA()
                }
                await loadVideoLength(for: urlB) { length in
                        videoLengthB = length
                        endTimeB = length
                }
                await extractThumbnails(from: urlB) { images in
                        thumbnailsB = images
                        selectedEndIndexB = images.count - 1 // 设置红色为最后一帧
                        updateFrameCountB()
                }
        }
        
        @MainActor
        private func loadVideoLength(for url: URL, completion: @escaping (Double) -> Void) async {
                let asset = AVAsset(url: url)
                do {
                        let duration = try await asset.load(.duration)
                        completion(CMTimeGetSeconds(duration))
                } catch {
                        print("Error loading video duration: \(error)")
                }
        }
}

func extractThumbnails(from url: URL, completion: @escaping ([UIImage]) -> Void) async {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var times = [NSValue]()
        guard let duration = try? await asset.load(.duration) else {
                return
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        let step = min(frameInterval, durationSeconds / Double(10)) // 确保至少有10个关键帧
        for i in stride(from: 0.0, to: durationSeconds, by: step) {
                let time = CMTime(seconds: i, preferredTimescale: 600)
                times.append(NSValue(time: time))
        }
        
        var images = [UIImage]()
        let lock = NSLock()
        let dispatchGroup = DispatchGroup()
        
        for time in times {
                dispatchGroup.enter()
                generator.generateCGImagesAsynchronously(forTimes: [time]) { _, image, _, _, error in
                        if let image = image {
                                lock.lock()
                                images.append(UIImage(cgImage: image))
                                lock.unlock()
                        }
                        dispatchGroup.leave()
                }
        }
        
        dispatchGroup.notify(queue: .main) {
                completion(images)
        }
}
