import SwiftUI
import AVKit
import AVFoundation
import PhotosUI

struct VideoPickerView: View {
        @ObservedObject var videoController: VideoAlignment
        @State private var showVideoPicker = false
        @State private var showVideoRecording = false
        @State private var showActionSheet = false
        
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
                                        showActionSheet = true
                                }) {
                                        Image(systemName: "plus")
                                                .font(.largeTitle)
                                                .padding()
                                                .frame(height: 200)
                                                .frame(maxWidth: .infinity)
                                                .background(Color.gray.opacity(0.3))
                                                .cornerRadius(10)
                                }
                                .actionSheet(isPresented: $showActionSheet) {
                                        ActionSheet(
                                                title: Text("Select an option"),
                                                buttons: [
                                                        .default(Text("Record Video")) {
                                                                showVideoRecording = true
                                                        },
                                                        .default(Text("Load from Gallery")) {
                                                                showVideoPicker = true
                                                        },
                                                        .cancel()
                                                ]
                                        )
                                }
                        }
                }
                .sheet(isPresented: $showVideoPicker) {
                        PHPickerViewController.View(videoPicked: { url in
                                showVideoPicker = false
                                videoController.prepareVideoInBackground(url: url)
                        })
                }
                .sheet(isPresented: $showVideoRecording) {
                        VideoRecordingView(videoPicked: { url in
                                showVideoRecording = false
                                videoController.prepareVideoInBackground(url: url)
                        })
                }
        }
}

struct VideoRecordingView: UIViewControllerRepresentable {
        var videoPicked: (URL) -> Void
        
        func makeCoordinator() -> Coordinator {
                return Coordinator(parent: self)
        }
        
        func makeUIViewController(context: Context) -> UIImagePickerController {
                let picker = UIImagePickerController()
                picker.delegate = context.coordinator
                picker.sourceType = .camera
                picker.mediaTypes = ["public.movie"]
                picker.videoMaximumDuration = 10.0
                picker.allowsEditing = false
                return picker
        }
        
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        
        class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
                let parent: VideoRecordingView
                
                init(parent: VideoRecordingView) {
                        self.parent = parent
                }
                
                func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                        picker.dismiss(animated: true, completion: nil)
                }
                
                func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
                        guard let mediaURL = info[.mediaURL] as? URL else { return }
                        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                        let newFileName = UUID().uuidString + ".mp4"
                        let newURL = tempDirectory.appendingPathComponent(newFileName)
                        
                        do {
                                try FileManager.default.copyItem(at: mediaURL, to: newURL)
                                DispatchQueue.main.async {
                                        self.parent.videoPicked(newURL)
                                }
                        } catch {
                                print("Error copying file to temporary directory: \(error.localizedDescription)")
                        }
                        
                        picker.dismiss(animated: true, completion: nil)
                }
        }
}
