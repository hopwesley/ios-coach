//
//  VideoPickerView.swift
//  SportsCoach
//
//  Created by wesley on 2024/7/4.
//

import SwiftUI
import AVKit
import AVFoundation
import PhotosUI

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
