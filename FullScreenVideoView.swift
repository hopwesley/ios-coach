//
//  FullScreenVideoView.swift
//  Efficiency Lab
//
//  Created by wesley on 2024/7/13.
//

import SwiftUI
import AVKit

class VideoPlayerViewModel: ObservableObject {
        @Published var player: AVPlayer
        @Published var playerCurrentTime: Double = 0
        @Published var playerDuration: Double = 0
        @Published var isEditingSlider: Bool = false
        
        private var timeObserverToken: Any?
        
        init(url: URL) {
                self.player = AVPlayer(url: url)
                self.addPeriodicTimeObserver()
        }
        
        deinit {
                if let token = timeObserverToken {
                        player.removeTimeObserver(token)
                        timeObserverToken = nil
                }
        }
        
        private func addPeriodicTimeObserver() {
                let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                        guard let self = self else { return }
                        guard !self.isEditingSlider else { return }
                        DispatchQueue.main.async {
                                self.playerCurrentTime = CMTimeGetSeconds(time)
                                print("playerCurrentTime time=>\(self.playerCurrentTime)")
                        }
                }
        }
        
        func sliderEditingChanged(editingStarted: Bool) {
                isEditingSlider = editingStarted
                if !editingStarted {
                        let targetTime = CMTime(seconds: playerCurrentTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                        print("target time=>\(targetTime)")
                        
                        // 暂停时间观察器
                        if let token = timeObserverToken {
                                player.removeTimeObserver(token)
                                timeObserverToken = nil
                        }
                        
                        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                                guard let self = self else { return }
                                DispatchQueue.main.async {
                                        self.isEditingSlider = false
                                        // 重新添加时间观察器
                                        self.addPeriodicTimeObserver()
                                }
                        }
                }
        }
        
        func prepareVideoTime() async {
                guard let item = player.currentItem,
                      let duration = try? await item.asset.load(.duration) else {
                        return
                }
                DispatchQueue.main.async {
                        self.playerDuration = CMTimeGetSeconds(duration)
                        print("playerDuration time=>\(self.playerDuration)")
                }
        }
}

struct FullScreenVideoView: View {
        @StateObject private var viewModel: VideoPlayerViewModel
        @Environment(\.presentationMode) var presentationMode
        
        init(url: URL) {
                _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(url: url))
        }
        
        var body: some View {
                VStack {
                        VideoPlayer(player: viewModel.player)
                                .onAppear {
                                        viewModel.player.play()
                                        Task {
                                                await viewModel.prepareVideoTime()
                                        }
                                }
                                .onDisappear {
                                        viewModel.player.pause()
                                }
                                .edgesIgnoringSafeArea(.all)
                                .onTapGesture {
                                        presentationMode.wrappedValue.dismiss()
                                }
                        
                        Slider(value: $viewModel.playerCurrentTime, in: 0...viewModel.playerDuration, onEditingChanged: viewModel.sliderEditingChanged)
                                .padding()
                                .accentColor(.white)
                }
                .background(Color.black)
        }
}
