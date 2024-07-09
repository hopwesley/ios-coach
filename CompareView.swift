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
        
        @State private var playerA: AVPlayer = AVPlayer()
        @State private var playerB: AVPlayer = AVPlayer()
        
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
                                                        .frame(height: 200)
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
                                                        .background(Color.black)
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
                }
                .disabled(isProcessing)
                .onAppear {
                        updatePlayers()
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
