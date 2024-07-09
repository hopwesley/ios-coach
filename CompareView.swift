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
                                        }
                                }
                                .padding(20) // Add padding around the entire content
                                .background(Color.white) // Add a white background
                                .cornerRadius(10) // Apply corner radius to the entire view
                                .shadow(radius: 5) // Add shadow for better visibility
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
}

#Preview {
        CompareView()
}

struct FullScreenVideoView: View {
    var url: URL
    @Environment(\.presentationMode) var presentationMode
    @State private var player: AVPlayer // 使用状态变量来管理播放器

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url)) // 初始化播放器并设置视频URL
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player.play() // 视图出现时开始播放
            }
            .onDisappear {
                player.pause() // 视图消失时暂停播放，避免在后台继续播放
            }
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                presentationMode.wrappedValue.dismiss() // 点击后退出全屏
            }
    }
}
