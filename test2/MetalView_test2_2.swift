import SwiftUI
import AVFoundation
import CoreImage
import MetalKit
import PhotosUI

struct MetalView_test2_2: View {
        @StateObject private var viewModel = VideoProcessingViewModel2()
        @State private var showImagePicker = false
        
        var body: some View {
                VStack {
                        if let processingTime = viewModel.processingTime {
                                Text("Processing Time: \(processingTime, specifier: "%.2f") seconds")
                                        .font(.headline)
                                        .padding()
                                        .background(Color.white)
                                        .cornerRadius(10)
                                        .shadow(radius: 10)
                                        .padding(.top, 40)
                                        .frame(maxWidth: .infinity, alignment: .center)
                        }
                        
                        Button(action: {
                                showImagePicker = true
                        }) {
                                Text("Load Video from Gallery")
                                        .font(.headline)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                        .padding(.top, 40)
                                        .shadow(radius: 10)
                        }
                        .padding()
                        .sheet(isPresented: $showImagePicker) {
                                PHPickerViewController.View(videoPicked: { url in
                                        showImagePicker = false
                                        viewModel.processVideo(from: url)
                                })
                        }
                        
                        ScrollView {
                                VStack(spacing: 10) {
                                        ForEach(viewModel.images, id: \.self) { image in
                                                Image(uiImage: image)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(maxWidth: .infinity)
                                        }
                                }
                                .padding()
                        }
                }
                .edgesIgnoringSafeArea(.all)
        }
}

class VideoProcessingViewModel2: ObservableObject {
        @Published var images: [UIImage] = []
        @Published var processingTime: Double?
        
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var context: CIContext!
        
        init() {
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                context = CIContext(mtlDevice: device)
        }
        
        func processVideo(from url: URL)  {
                let startTime = Date()
                let fileManager = FileManager.default
                let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let newFileName = UUID().uuidString + ".mp4" // 使用UUID作为新文件名
                let newURL = documentsPath.appendingPathComponent(newFileName)
                
                do {
                        // 复制文件到文档目录
                        try fileManager.copyItem(at: url, to: newURL)
                        print("File copied to: \(newURL.path)")
                        
                       let grayImages =  readAllFramesAndConvertToGray2(url: newURL)
                        self.images = grayImages
                        print("image count:---->:",grayImages.count)
                        let endTime = Date()
                        self.processingTime = endTime.timeIntervalSince(startTime)
                } catch {
                        print("Error during processing: \(error.localizedDescription)")
                }
        }
        
        func readAllFramesAndConvertToGray(url: URL)  -> [UIImage] {
                var grayImages: [UIImage] = []
                let queue = DispatchQueue(label: "videoProcessingQueue", attributes: .concurrent)
                let group = DispatchGroup()
                
                do {
                        let asset = AVAsset(url: url)
                        let assetReader = try AVAssetReader(asset: asset)
                        
                        let alltracks =    asset.tracks(withMediaType: .video)
                        print("tack size:====>",alltracks.count)
                        guard let videoTrack = alltracks.first else {
                                print("No video track found in asset")
                                return []
                        }
                        
                        let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                        assetReader.add(trackReaderOutput)
                        
                        if assetReader.startReading() == false {
                                print("Could not start reading the asset")
                                return []
                        }
                        
                        while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
                                group.enter()
                                queue.async {
                                        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                                                let ciImage = CIImage(cvImageBuffer: imageBuffer)
                                                let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
                                                
//                                                print("---------->>>> copy gray scale data......")
                                                if let cgImage = self.context.createCGImage(grayscale, from: grayscale.extent) {
                                                        grayImages.append(UIImage(cgImage: cgImage))
                                                }
                                        }
                                        group.leave()
                                }
                        }
                } catch {
                        print("Error creating asset reader: \(error)")
                }
                
                group.wait()
                return grayImages
        }
        
        
                func readAllFramesAndConvertToGray2(url: URL) -> [UIImage] {
                        var grayImages: [UIImage] = []
                        do {
                                let asset = AVAsset(url: url)
                                let assetReader = try AVAssetReader(asset: asset)
        
                                guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                                        print("No video track found in asset")
                                        return []
                                }
        
                                let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                                assetReader.add(trackReaderOutput)
        
                                if assetReader.startReading() == false {
                                        print("Could not start reading the asset")
                                        return []
                                }
        
                                while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
        
                                        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                                                let ciImage = CIImage(cvImageBuffer: imageBuffer)
                                                let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        
                                                print("---------->>>> copy gray scale data......")
                                                if let cgImage = self.context.createCGImage(grayscale, from: grayscale.extent) {
                                                        grayImages.append(UIImage(cgImage: cgImage))
                                                }
                                        }
                                }
        
                        } catch {
                                print("Error creating asset reader: \(error)")
                        }
                        return grayImages
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
                                        let newFileName = UUID().uuidString + ".mp4" // 使用UUID作为新文件名
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
