//
//  CompareView.swift
//  SportsCoach
//
//  Created by wesley on 2024/7/4.
//


import SwiftUI
import AVKit
import AVFoundation
import PhotosUI

struct CompareView: View {
        @State var urlA: URL?
        @State var urlB: URL?
        @StateObject private var compareror = VideoCompare()
        @State private var isProcessing = false
        var processingTime: Double?
        var comparedUrl: URL?
        
        var body: some View {
                ZStack {
                        ScrollView {
                                VStack(spacing: 20) {
                                        if let time = processingTime {
                                                Text("处理时间: \(time, specifier: "%.2f") 秒")
                                                        .padding(.top, 20) // Adjust top padding
                                        }
                                        
                                        if let urlA = urlA, let urlB = urlB {
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
                }
                .disabled(isProcessing) // Disable all interactions when processing
        }
        
        func compareVideo() {
                guard let aUrl = urlA, let bUrl = urlB else {
                        print("video invalid!")
                        return
                }
                DispatchQueue.main.async {
                        self.isProcessing = true
                }
                Task {
                        do {
                                try await compareror.CompareAction(videoA: aUrl, videoB: bUrl)
                                DispatchQueue.main.async {
                                        self.isProcessing = false
                                        // self.comparedUrl = // Set this to the result of CompareAction
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
