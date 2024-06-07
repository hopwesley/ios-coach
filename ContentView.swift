import SwiftUI
import AVKit
import PhotosUI

struct ContentView: View {
        @StateObject private var viewModel = VideoProcessingViewModel()
        @State private var showImagePicker1 = false
        @State private var showImagePicker2 = false
        
        var body: some View {
                VStack {
                        // 第一行：统计信息
                        VStack(alignment: .leading) {
                                Text("统计信息")
                                        .font(.headline)
                                HStack {
                                        Text("视频1时长: \(viewModel.video1DurationText)")
                                        Spacer()
                                        Text("视频1帧数: \(viewModel.video1FrameCount)")
                                        Spacer()
                                        Text("视频1名称: \(viewModel.video1Name)")
                                }
                                HStack {
                                        Text("视频2时长: \(viewModel.video2DurationText)")
                                        Spacer()
                                        Text("视频2帧数: \(viewModel.video2FrameCount)")
                                        Spacer()
                                        Text("视频2名称: \(viewModel.video2Name)")
                                }
                                HStack {
                                        Text("处理进度: \(viewModel.progressText)")
                                        Spacer()
                                        Text("运行时间: \(viewModel.elapsedTimeText)")
                                }
                        }
                        .padding()
                        .border(Color.gray, width: 1)
                        
                        // 第二行：加载第一个视频
                        VStack {
                                ZStack {
                                        if let videoURL = viewModel.video1URL {
                                                VideoPlayer(player: AVPlayer(url: videoURL))
                                                        .frame(height: 200)
                                                Button(action: {
                                                        viewModel.removeVideo1()
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
                                                        Text("点击加载视频(最长15s)")
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
                                        viewModel.loadVideo1(url: url)
                                })
                        }
                        
                        // 第三行：加载第二个视频
                        VStack {
                                ZStack {
                                        if let videoURL = viewModel.video2URL {
                                                VideoPlayer(player: AVPlayer(url: videoURL))
                                                        .frame(height: 200)
                                                Button(action: {
                                                        viewModel.removeVideo2()
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
                                                        Text("点击加载视频(最长15s)")
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
                                        viewModel.loadVideo2(url: url)
                                })
                        }
                        
                        // 第四行：按钮操作
                        HStack {
                                Button(action: {
                                        viewModel.convertToGray()
                                }) {
                                        Text("转为灰度")
                                }
                                Button(action: {
                                        viewModel.startAlignment()
                                }) {
                                        Text("开始对齐")
                                }
                                Button(action: {
                                        viewModel.startComparison()
                                }) {
                                        Text("开始对比")
                                }
                                Button(action: {
                                        viewModel.reset()
                                }) {
                                        Text("重新加载")
                                }
                        }
                        .padding()
                        
                        // 第五行：处理结果
                        VStack {
                                Text("处理结果")
                                        .font(.headline)
                                Text(viewModel.resultText)
                        }
                        .padding()
                        .border(Color.gray, width: 1)
                }
                .padding()
        }
}

class VideoProcessingViewModel: ObservableObject {
        @Published var video1URL: URL?
        @Published var video2URL: URL?
        @Published var video1DurationText: String = "00:00"
        @Published var video1FrameCount: Int = 0
        @Published var video1Name: String = ""
        @Published var video2DurationText: String = "00:00"
        @Published var video2FrameCount: Int = 0
        @Published var video2Name: String = ""
        @Published var progressText: String = "0%"
        @Published var elapsedTimeText: String = "0s"
        @Published var resultText: String = ""
        
        
        
        func loadVideo(url: URL, sourceID:Int) {
                let asset = AVAsset(url: url)
                let duration = CMTimeGetSeconds(asset.duration)
                if duration > 15 {
                        // 提示用户视频不能超过15秒
                        print("视频时长不能超过15秒")
                        return
                }
                if (sourceID == 1){
                        video1URL = url
                        video1Name = url.lastPathComponent
                        video1DurationText = formatTime(duration)
                }else if (sourceID == 2){
                        video2URL = url
                        video2Name = url.lastPathComponent
                        video2DurationText = formatTime(duration)
                }
        }
        
        func loadVideo2(url: URL) {
                
                loadVideo(url: url, sourceID: 2)
        }
        func loadVideo1(url: URL) {
                loadVideo(url: url, sourceID: 1)
        }
        
        func formatTime(_ seconds: Double) -> String {
                let minutes = Int(seconds) / 60
                let seconds = Int(seconds) % 60
                return String(format: "%02d:%02d", minutes, seconds)
        }
        
        func removeVideo1() {
                video1URL = nil
        }
        
        func removeVideo2() {
                video2URL = nil
        }
        
        func convertToGray() {
        }
        
        func startAlignment() {
        }
        
        func startComparison() {
        }
        
        func reset() {
        }
}

extension PHPickerViewController {
        struct View: UIViewControllerRepresentable {
                var videoPicked: (URL) -> Void
                
                class Coordinator: PHPickerViewControllerDelegate {
                        var parent: View
                        
                        init(parent: View) {
                                self.parent = parent
                        }
                        
                        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
                                picker.dismiss(animated: true)
                                guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else { return }
                                
                                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { (url, error) in
                                        guard let url = url else {
                                                print("Error loading file representation: \(error?.localizedDescription ?? "Unknown error")")
                                                return
                                        }
                                        let fileManager = FileManager.default
                                        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                        let newFileName = UUID().uuidString + ".mp4"
                                        let newURL = documentsPath.appendingPathComponent(newFileName)
                                        
                                        do {
                                                try fileManager.copyItem(at: url, to: newURL)
                                                DispatchQueue.main.async {
                                                        self.parent.videoPicked(newURL)
                                                }
                                        } catch {
                                                print("Error copying file to documents directory: \(error.localizedDescription)")
                                        }
                                }
                        }
                }
                
                func makeCoordinator() -> Coordinator {
                        return Coordinator(parent: self)
                }
                
                func makeUIViewController(context: Context) -> PHPickerViewController {
                        var configuration = PHPickerConfiguration()
                        configuration.filter = .videos
                        configuration.selectionLimit = 1
                        let picker = PHPickerViewController(configuration: configuration)
                        picker.delegate = context.coordinator
                        return picker
                }
                
                func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
        }
}
