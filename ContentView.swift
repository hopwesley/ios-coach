import SwiftUI
import _AVKit_SwiftUI
import PhotosUI

let constMaxVideoLen = 20.0
struct ContentView: View {
    @StateObject private var viewModelVideo1 = VideoProcess()
    @StateObject private var viewModelVideo2 = VideoProcess()
    @State private var showImagePicker1 = false
    @State private var showImagePicker2 = false
    @State private var grayImg1: UIImage?
    @State private var grayImg2: UIImage?
    
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
                    Button("Convert and Show Image") {
                        DispatchQueue.global(qos: .userInitiated).async {
                            var image1: UIImage?
                            var image2: UIImage?
                            print("------>>>video 1 count:",viewModelVideo1.videoGrayTextures.count)
                            if let texture1 = viewModelVideo1.videoGrayTextures.first {
                                let arr = getPixelDataFromTexture(texture: texture1)
                                print(arr ?? [])
                                image1 = textureToImage(texture: texture1)
                            }
                            
                            print("------>>>video 2 count:",viewModelVideo2.videoGrayTextures.count)
                            if let texture2 = viewModelVideo2.videoGrayTextures.first {
                                image2 = textureToImage(texture: texture2)
                            }
                            DispatchQueue.main.async {
                                self.grayImg1 = image1
                                self.grayImg2 = image2
                            }
                        }
                    }
                    Text("视频1灰度图：")
                    if let image1 = grayImg1 {
                        Image(uiImage: image1)
                            .resizable()
                            .frame(width: 300, height: 300)
                            .aspectRatio(contentMode: .fit)
                    }
                    
                    Text("视频2灰度图：")
                    if let image2 = grayImg2 {
                        Image(uiImage: image2)
                            .resizable()
                            .frame(width: 300, height: 300)
                            .aspectRatio(contentMode: .fit)
                    }
                    
                }
                .padding()
                .border(Color.gray, width: 1)
            }
            .padding()
        }
    }
}

