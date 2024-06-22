import SwiftUI
import AVFoundation
import _AVKit_SwiftUI
import PhotosUI


struct ContentView: View {
        
        @StateObject private var videoCtlA = AlignController()
        @StateObject private var videoCtlB = AlignController()
        
        var body: some View {
                ScrollView {
                        VStack {
                                VideoPickerView(videoController: videoCtlA)
                                VideoPickerView(videoController: videoCtlB)
                        }
                        VStack{
                                Button(action: {
                                        videoCtlA.AlignVideo()
                                }) {
                                        Text("测试帧梯度")
                                }.frame(width: 160, height: 80).background(Color.gray)
                                Button(action: {
                                        processingTimeAlign()
                                }) {
                                        Text("转为灰度")
                                }.frame(width: 160, height: 80).background(Color.gray)
                        }
                }
        }
        
        func processingTimeAlign(){
                
                guard let histogramA = videoCtlA.histogramOfAllFrame(),
                      let  histogramB = videoCtlB.histogramOfAllFrame() else{
                        return
                }
                
                guard let (offsetA,offsetB) = findBestAlingOffset(histoA: histogramA, histoB: histogramB) else{
                        return;
                }
                
                videoCihper(url:videoCtlA.videoURL!,offset:offsetA)
                videoCihper(url:videoCtlB.videoURL!,offset:offsetB)
        }
}


struct VideoPickerView: View {
        
        @ObservedObject var videoController: AlignController
        @State private var showVideoPicker = false
        
        var body: some View {
                VStack {
                        if let videoUrl = videoController.videoURL {
                                VideoPlayer(player: AVPlayer(url: videoUrl))
                                        .frame(height: 400) // 固定高度
                                        .background(Color.black) // 设置背景颜色以确保视频显示区域
                                Button(action: {
                                        videoController.removeVideo()
                                }) {
                                        Image(systemName: "trash")
                                                .foregroundColor(.red)
                                                .padding()
                                                .background(Color.white)
                                                .cornerRadius(20)
                                }
                                if let info = videoController.videoInfo{
                                        Text(info)
                                }
                        } else {
                                Button(action: {
                                        showVideoPicker = true
                                }) {
                                        Image(systemName: "plus")
                                                .font(.largeTitle)
                                                .padding()
                                                .frame(height: 200) // 固定高度
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
