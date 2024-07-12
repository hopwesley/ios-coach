import SwiftUI
import AVKit
import AVFoundation
import PhotosUI

struct CompareView: View {
        @State var urlA: URL?
        @State var urlB: URL?
        @StateObject private var compareror = VideoCompare()
        @State private var isProcessing = false
        var alignTime: Double?
        @State var compareTime: Double? = nil
        @State private var isImageFullScreen = false // 状态变量，用于管理图片的显示状态
        @State private var showFullScreenVideo = false // 控制全屏视频视图的显示
        
        @State private var playerA: AVPlayer = AVPlayer()
        @State private var playerB: AVPlayer = AVPlayer()
        @State private var fullScreenVideoURL: URL? // 存储要全屏播放的视频URL
        
        
        @State private var showAlert = false
        @State private var alertMessage = ""
        
        var body: some View {
                ZStack {
                        ScrollView {
                                VStack(spacing: 20) {
                                        if let time = alignTime {
                                                Text("对齐时间: \(time, specifier: "%.2f") 秒")
                                                        .padding(.top, 20)
                                        }
                                        HStack(spacing: 20) {
                                                VideoPlayer(player: playerA)
                                                        .frame(height: 200)
                                                        .background(Color.black)
                                                
                                                VideoPlayer(player: playerB)
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
                                        .padding(.top, 20)
                                        if let cTime = compareTime {
                                                Text("对比时间: \(cTime, specifier: "%.2f") 秒")
                                        }
                                        
                                        if let tmpFrameImg = compareror.tmpFrameImg {
                                                Image(uiImage: tmpFrameImg)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(height: 400)
                                                        .background(Color.black)
                                                        .onTapGesture {
                                                                withAnimation {
                                                                        isImageFullScreen = true
                                                                }
                                                        }
                                        }
                                        
                                        if let comparedUrl = compareror.comparedUrl {
                                                VideoPlayer(player: AVPlayer(url: comparedUrl))
                                                        .frame(height: 200)
                                                        .background(Color.black).onTapGesture {
                                                                self.fullScreenVideoURL = comparedUrl
                                                                self.showFullScreenVideo = true
                                                        }
                                                Button(action: {
                                                        saveVideoToAlbum(videoURL: comparedUrl)
                                                }) {
                                                        Text("保存视频")
                                                                .frame(width: 160, height: 80)
                                                                .background(Color.blue)
                                                                .foregroundColor(.white)
                                                                .cornerRadius(10)
                                                }
                                        }
                                }
                                .padding(20) // Add padding around the entire content
                                .background(Color.white) // Add a white background
                                .cornerRadius(10) // Apply corner radius to the entire view
                                .shadow(radius: 5) // Add shadow for better visibility
                        } .alert(isPresented: $showAlert) {
                                Alert(title: Text("保存视频"), message: Text(alertMessage), dismissButton: .default(Text("确定")))
                        }
                        
                        if isProcessing {
                                VStack {
                                        Text(compareror.processingMessage)
                                                .padding()
                                                .background(Color.black.opacity(0.75))
                                                .cornerRadius(10)
                                                .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.5).edgesIgnoringSafeArea(.all))
                                .zIndex(1)
                        }
                        
                        if isImageFullScreen {
                                VStack {
                                        Spacer()
                                        
                                        Image(uiImage: compareror.tmpFrameImg!)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(Color.black)
                                                .onTapGesture {
                                                        withAnimation {
                                                                isImageFullScreen = false
                                                        }
                                                }
                                        
                                        Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.9).edgesIgnoringSafeArea(.all))
                                .zIndex(2)
                        }
                        if showFullScreenVideo, let fullScreenVideoURL = fullScreenVideoURL {
                                FullScreenVideoView(url: fullScreenVideoURL)
                        }
                        
                }
                .disabled(isProcessing)
                .onAppear {
                        updatePlayers()
                }
                .sheet(isPresented: $showFullScreenVideo) {
                        if let fullScreenVideoURL = fullScreenVideoURL {
                                FullScreenVideoView(url: fullScreenVideoURL)
                        }
                }
        }
        func updatePlayers() {
                if let urlA = urlA {
                        playerA.replaceCurrentItem(with: AVPlayerItem(url: urlA))
                }
                if let urlB = urlB {
                        playerB.replaceCurrentItem(with: AVPlayerItem(url: urlB))
                }
        }
        func compareVideo() {
                guard let aUrl = urlA, let bUrl = urlB else {
                        print("video invalid!")
                        return
                }
                let startTime = Date()
                
                DispatchQueue.main.async {
                        self.isProcessing = true
                }
                Task {
                        do {
                                try await compareror.CompareAction(videoA: aUrl, videoB: bUrl)
                                let endTime = Date()
                                let executionTime = endTime.timeIntervalSince(startTime)
                                DispatchQueue.main.async {
                                        self.isProcessing = false
                                        self.compareTime = executionTime
                                }
                        } catch {
                                DispatchQueue.main.async {
                                        self.isProcessing = false
                                        self.compareror.processingMessage = "处理失败，请重试。"
                                }
                        }
                }
        }
        
        func saveVideoToAlbum(videoURL: URL) {
                PHPhotoLibrary.requestAuthorization { status in
                        guard status == .authorized else {
                                DispatchQueue.main.async {
                                        self.alertMessage = "未授权访问相册。"
                                        self.showAlert = true
                                }
                                return
                        }
                        PHPhotoLibrary.shared().performChanges({
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                        }) { success, error in
                                DispatchQueue.main.async {
                                        if success {
                                                self.alertMessage = "视频已保存到相册。"
                                        } else {
                                                self.alertMessage = "视频保存失败: \(error?.localizedDescription ?? "未知错误")"
                                        }
                                        self.showAlert = true
                                }
                        }
                }
        }
}


struct FullScreenVideoView: View {
        var url: URL
        @Environment(\.presentationMode) var presentationMode
        @State private var player: AVPlayer
        @State private var playerCurrentTime: Double = 0
        @State private var playerDuration: Double = 0
        
        init(url: URL) {
                self.url = url
                _player = State(initialValue: AVPlayer(url: url))
        }
        
        var body: some View {
                VStack {
                        VideoPlayer(player: player)
                                .onAppear {
                                        player.play()
                                        addPeriodicTimeObserver()
                                        Task{
                                                await prepareVideoTime()
                                        }
                                }
                                .onDisappear {
                                        player.pause()
                                }
                                .edgesIgnoringSafeArea(.all)
                                .onTapGesture {
                                        presentationMode.wrappedValue.dismiss()
                                }
                        
                        // Custom slider for video progress
                        Slider(value: $playerCurrentTime, in: 0...playerDuration, onEditingChanged: sliderEditingChanged)
                                .padding()
                                .accentColor(.white)
                }
                .background(Color.black)
        }
        
        private func addPeriodicTimeObserver() {
                let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                        playerCurrentTime = CMTimeGetSeconds(time)
                }
        }
        
        private func sliderEditingChanged(editingStarted: Bool) {
                if editingStarted == false {
                        let targetTime = CMTime(seconds: playerCurrentTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                        player.seek(to: targetTime)
                }
        }
        
        private func prepareVideoTime() async{
                guard let item = player.currentItem,
                      let duration = try? await item.asset.load(.duration) else{
                        return
                }
                playerDuration = CMTimeGetSeconds(duration)
        }
}
