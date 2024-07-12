import SwiftUI
import AVFoundation
import Combine

struct ManualAlignView: View {
        var urlA: URL
        var urlB: URL
        
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
        
        @State private var scrollViewProxyA: ScrollViewProxy?
        @State private var scrollViewProxyB: ScrollViewProxy?
        
        
        init(urlA: URL, urlB: URL) {
                self.urlA = urlA
                self.urlB = urlB
        }
        
        var body: some View {
                VStack {
                        // Video A
                        ScrollView(.horizontal, showsIndicators: true) {
                                ScrollViewReader { proxy in
                                        HStack {
                                                ForEach(thumbnailsA.indices, id: \.self) { index in
                                                        ZStack {
                                                                if index == selectedStartIndexA {
                                                                        Rectangle()
                                                                                .fill(Color.green)
                                                                                .frame(width: 100, height: 100)
                                                                } else if index == selectedEndIndexA {
                                                                        Rectangle()
                                                                                .fill(Color.red)
                                                                                .frame(width: 100, height: 100)
                                                                }
                                                                Image(uiImage: thumbnailsA[index])
                                                                        .resizable()
                                                                        .aspectRatio(contentMode: .fit)
                                                                        .frame(height: 100)
                                                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                                        }
                                                        .padding(5) // 添加内边距
                                                        .border(Color.black, width: 1) // 添加边框
                                                        .id(index) // 确保每个缩略图都有唯一的ID
                                                }
                                        }
                                        .padding()
                                        .onAppear {
                                                scrollViewProxyA = proxy
                                        }
                                }
                        }
                        .scrollIndicators(.visible)
                        
                        
                        Text("Start Time A: \(startTimeA, specifier: "%.2f") seconds")
                        Slider(value: $startTimeA, in: 0...videoLengthA, step: 0.01)
                                .onChange(of: startTimeA) { newValue in
                                        if startTimeA >= endTimeA {
                                                startTimeA = endTimeA - 0.01
                                        }
                                        updateSelectedIndex(for: startTimeA, videoLength: videoLengthA, thumbnails: thumbnailsA, isStart: true, isA: true)
                                        scrollToSelectedIndex(selectedStartIndexA, isA: true)
                                }
                        
                        Text("End Time A: \(endTimeA, specifier: "%.2f") seconds")
                        Slider(value: $endTimeA, in: 0...videoLengthA, step: 0.01)
                                .onChange(of: endTimeA) { newValue in
                                        if endTimeA <= startTimeA {
                                                endTimeA = startTimeA + 0.01
                                        }
                                        updateSelectedIndex(for: endTimeA, videoLength: videoLengthA, thumbnails: thumbnailsA, isStart: false, isA: true)
                                        scrollToSelectedIndex(selectedEndIndexA, isA: true)
                                }
                        
                        Divider().padding()
                        
                        // Video B
                        ScrollView(.horizontal, showsIndicators: true) {
                                ScrollViewReader { proxy in
                                        HStack {
                                                ForEach(thumbnailsB.indices, id: \.self) { index in
                                                        ZStack {
                                                                if index == selectedStartIndexB {
                                                                        Rectangle()
                                                                                .fill(Color.green)
                                                                                .frame(width: 100, height: 100)
                                                                } else if index == selectedEndIndexB {
                                                                        Rectangle()
                                                                                .fill(Color.red)
                                                                                .frame(width: 100, height: 100)
                                                                }
                                                                Image(uiImage: thumbnailsB[index])
                                                                        .resizable()
                                                                        .aspectRatio(contentMode: .fit)
                                                                        .frame(height: 100)
                                                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                                        }
                                                        .padding(5) // 添加内边距
                                                        .border(Color.black, width: 1) // 添加边框
                                                        .id(index) // 确保每个缩略图都有唯一的ID
                                                }
                                        }
                                        .padding()
                                        .onAppear {
                                                scrollViewProxyB = proxy
                                        }
                                }
                        }
                        .scrollIndicators(.visible)
                        
                        
                        
                        Text("Start Time B: \(startTimeB, specifier: "%.2f") seconds")
                        Slider(value: $startTimeB, in: 0...videoLengthB, step: 0.01)
                                .onChange(of: startTimeB) { newValue in
                                        if startTimeB >= endTimeB {
                                                startTimeB = endTimeB - 0.01
                                        }
                                        updateSelectedIndex(for: startTimeB, videoLength: videoLengthB, thumbnails: thumbnailsB, isStart: true, isA: false)
                                        scrollToSelectedIndex(selectedStartIndexB, isA: false)
                                }
                        
                        Text("End Time B: \(endTimeB, specifier: "%.2f") seconds")
                        Slider(value: $endTimeB, in: 0...videoLengthB, step: 0.01)
                                .onChange(of: endTimeB) { newValue in
                                        if endTimeB <= startTimeB {
                                                endTimeB = startTimeB + 0.01
                                        }
                                        updateSelectedIndex(for: endTimeB, videoLength: videoLengthB, thumbnails: thumbnailsB, isStart: false, isA: false)
                                        scrollToSelectedIndex(selectedEndIndexB, isA: false)
                                }
                        
                        Button("Save") {
                                print("Video A - Start Time: \(startTimeA)s, End Time: \(endTimeA)s")
                                print("Video B - Start Time: \(startTimeB)s, End Time: \(endTimeB)s")
                                // Add your save logic here
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                .onAppear {
                        Task {
                                await loadVideoLength(for: urlA) { length in
                                        videoLengthA = length
                                        endTimeA = length
                                }
                                await extractThumbnails(from: urlA) { images in
                                        thumbnailsA = images
                                        selectedEndIndexA = images.count - 1 // 设置红色为最后一帧
                                }
                                await loadVideoLength(for: urlB) { length in
                                        videoLengthB = length
                                        endTimeB = length
                                }
                                await extractThumbnails(from: urlB) { images in
                                        thumbnailsB = images
                                        selectedEndIndexB = images.count - 1 // 设置红色为最后一帧
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
                } else {
                        if isStart {
                                selectedStartIndexB = index
                        } else {
                                selectedEndIndexB = index
                        }
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
        
        private func thumbnailBackgroundA(index: Int) -> Color {
                if index == selectedStartIndexA {
                        return Color.green
                } else if index == selectedEndIndexA {
                        return Color.red
                } else {
                        return Color.clear
                }
        }
        
        private func thumbnailBackgroundB(index: Int) -> Color {
                if index == selectedStartIndexB {
                        return Color.green
                } else if index == selectedEndIndexB {
                        return Color.red
                } else {
                        return Color.clear
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
        let step = durationSeconds / 10.0
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
