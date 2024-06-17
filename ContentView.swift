import SwiftUI
import _AVKit_SwiftUI
import PhotosUI

let constMaxVideoLen = 20.0
struct ContentView: View {
        @StateObject private var viewModelVideo1 = VideoProcess()
        @StateObject private var viewModelVideo2 = VideoProcess()
        @State private var showImagePicker1 = false
        @State private var showImagePicker2 = false
        
        var body: some View {
                ScrollView { // 添加 ScrollView
                        VStack {
                                // 第一行：统计信息
                                VStack(alignment: .leading) {
                                        Text("统计信息")
                                                .font(.headline)
                                        HStack {
                                                Text("视频1时长: \(viewModelVideo1.videoDurationText)")
                                                Spacer()
                                                Text("视频2时长: \(viewModelVideo2.videoDurationText)")
                                        }
                                        HStack {
                                                Text("视频1帧数: \(viewModelVideo1.videoFrameCount)")
                                                Spacer()
                                                Text("视频2帧数: \(viewModelVideo2.videoFrameCount)")
                                        }
                                        HStack {
                                                Text("视频1帧速率: \(viewModelVideo1.videoFrameRate)")
                                                Spacer()
                                                Text("视频2帧速率: \(viewModelVideo2.videoFrameRate)")
                                        }
                                }
                                .padding()
                                .border(Color.gray, width: 1)
                                
                                VStack {
                                        ZStack {
                                                if let videoURL = viewModelVideo1.videoURL {
                                                        VideoPlayer(player: AVPlayer(url: videoURL))
                                                                .frame(height: 200)
                                                        Button(action: {
                                                                viewModelVideo1.removeVideo()
                                                        }) {
                                                                Image(systemName: "trash")
                                                                        .foregroundColor(.red)
                                                                        .padding()
                                                                        .background(Color.white)
                                                                        .cornerRadius(20)
                                                        }
                                                        .offset(x: 140, y: -90)
                                                } else {
                                                        VStack {
                                                                Button(action: {
                                                                        showImagePicker1 = true
                                                                }) {
                                                                        Image(systemName: "plus")
                                                                                .font(.largeTitle)
                                                                                .padding()
                                                                }
                                                                Text("点击加载视频(最长20s)")
                                                                        .foregroundColor(.gray)
                                                        }
                                                        .frame(height: 200)
                                                        .border(Color.gray, width: 1)
                                                }
                                        }
                                }
                                .sheet(isPresented: $showImagePicker1) {
                                        PHPickerViewController.View(videoPicked: { url in
                                                showImagePicker1 = false
                                                viewModelVideo1.prepareVideoForGpu(url: url)
                                        })
                                }
                                
                                VStack {
                                        ZStack {
                                                if let videoURL = viewModelVideo2.videoURL {
                                                        VideoPlayer(player: AVPlayer(url: videoURL))
                                                                .frame(height: 200)
                                                        Button(action: {
                                                                viewModelVideo2.removeVideo()
                                                        }) {
                                                                Image(systemName: "trash")
                                                                        .foregroundColor(.red)
                                                                        .padding()
                                                                        .background(Color.white)
                                                                        .cornerRadius(20)
                                                        }
                                                        .offset(x: 140, y: -90)
                                                } else {
                                                        VStack {
                                                                Button(action: {
                                                                        showImagePicker2 = true
                                                                }) {
                                                                        Image(systemName: "plus")
                                                                                .font(.largeTitle)
                                                                                .padding()
                                                                }
                                                                Text("点击加载视频(最长20s)")
                                                                        .foregroundColor(.gray)
                                                        }
                                                        .frame(height: 200)
                                                        .border(Color.gray, width: 1)
                                                }
                                        }
                                }
                                .sheet(isPresented: $showImagePicker2) {
                                        PHPickerViewController.View(videoPicked: { url in
                                                showImagePicker2 = false
                                                viewModelVideo2.prepareVideoForGpu(url: url)
                                        })
                                }
                                
                                HStack {
                                        Button(action: {
                                                viewModelVideo1.convertToGray()
                                                viewModelVideo2.convertToGray()
                                        }) {
                                                Text("转为灰度")
                                        }
                                        Button(action: {
                                                
                                        }) {
                                                Text("开始对齐")
                                        }
                                        Button(action: {
                                                
                                        }) {
                                                Text("开始对比")
                                        }
                                        Button(action: {
                                                
                                        }) {
                                                Text("重新加载")
                                        }
                                }
                                .padding()
                                
                                VStack {
                                        Text("处理结果")
                                                .font(.headline)
                                }
                                VStack {
                                        Text("视频1灰度图：")
                                        if let image1 = viewModelVideo1.grayscaleImage {
                                                Image(uiImage: image1)
                                                        .frame(width: image1.size.width, height: image1.size.height)
                                        }
                                        
                                        Text("视频2灰度图：")
                                        if let image2 = viewModelVideo2.grayscaleImage {
                                                Image(uiImage: image2)
                                                        .frame(width: image2.size.width, height: image2.size.height)
                                        }
                                }
                                .padding()
                                .border(Color.gray, width: 1)
                        }
                        .padding()
                }
        }
}
