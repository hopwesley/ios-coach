import SwiftUI
import AVFoundation
import CoreImage
import MetalKit
import PhotosUI

/***
 [App] --(submit)--> [Command Queue] --(contains)--> [Command Buffer] --(configures)--> [Compute Encoder]
      \                                                     |
       \                                                    |
        \-----[CIContext] <-------------(utilizes)---------/
                |
                |
        (rendering images using GPU)

 ***/

struct MetalView_test2_3: View {
        @StateObject private var viewModel = VideoProcessingViewModel3()
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

class VideoProcessingViewModel3: ObservableObject {
        @Published var images: [UIImage] = []
        @Published var processingTime: Double?
        
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var context: CIContext!
        var library: MTLLibrary!
        var grayscalePipeline: MTLComputePipelineState!
        
        init() {
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                context = CIContext(mtlDevice: device)
                
                do {
                        library = device.makeDefaultLibrary()
                        let kernelFunction = library.makeFunction(name: "grayscaleKernel")
                        grayscalePipeline = try device.makeComputePipelineState(function: kernelFunction!)
                } catch {
                        print("Error initializing Metal: \(error)")
                }
        }
        
        func processVideo(from url: URL) {
                let startTime = Date()
                let fileManager = FileManager.default
                let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let newFileName = UUID().uuidString + ".mp4"
                let newURL = documentsPath.appendingPathComponent(newFileName)
                
                do {
                        try fileManager.copyItem(at: url, to: newURL)
                        print("File copied to: \(newURL.path)")
                        
                        DispatchQueue.global(qos: .userInitiated).async {
                                let grayImages = self.readAllFramesAndConvertToGray(url: newURL)
                                DispatchQueue.main.async {
                                        if let img = grayImages{
                                                self.images = [img]
                                        }
                                        
                                        let endTime = Date()
                                        self.processingTime = endTime.timeIntervalSince(startTime)
                                }
                        }
                } catch {
                        print("Error during processing: \(error.localizedDescription)")
                }
        }
        
        func readAllFramesAndConvertToGray(url: URL) -> UIImage? {
                
                var lastImg:UIImage? = nil
                do {
                        let asset = AVAsset(url: url)
                        let assetReader = try AVAssetReader(asset: asset)
                        
                        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                                print("No video track found in asset")
                                return nil
                        }
                        
                        let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                        assetReader.add(trackReaderOutput)
                        
                        if assetReader.startReading() == false {
                                print("Could not start reading the asset")
                                return nil
                        }
                        while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
                                autoreleasepool {
                                        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                                                let ciImage = CIImage(cvImageBuffer: imageBuffer)
                                                let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)
                                                let textureLoader = MTKTextureLoader(device: self.device)
                                                let texture = try! textureLoader.newTexture(cgImage: cgImage!, options: nil)
                                                let grayTexture = self.processImageWithMetal(texture: texture)
                                                let ciGrayImage = CIImage(mtlTexture: grayTexture, options: nil)!
                                                
                                                if let cgGrayImage = self.context.createCGImage(ciGrayImage, from: ciGrayImage.extent) {
                                                        lastImg = UIImage(cgImage: cgGrayImage)
                                                        print("------>>> new img success")
                                                }
                                        }
                                }
                        }
                } catch {
                        print("Error creating asset reader: \(error)")
                }
                
                return lastImg
        }
        
        
        func processImageWithMetal(texture: MTLTexture) -> MTLTexture {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: texture.width,
                        height: texture.height,
                        mipmapped: false
                )
                descriptor.usage = [.shaderRead, .shaderWrite]
                let outputTexture = device.makeTexture(descriptor: descriptor)!
                
                let commandBuffer = commandQueue.makeCommandBuffer()!
                let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
                computeEncoder.setComputePipelineState(grayscalePipeline)
                computeEncoder.setTexture(texture, index: 0)
                computeEncoder.setTexture(outputTexture, index: 1)
                
                let threadgroupWidth = grayscalePipeline.threadExecutionWidth
                let threadgroupHeight = grayscalePipeline.maxTotalThreadsPerThreadgroup / threadgroupWidth
                let threadsPerThreadgroup = MTLSize(width: threadgroupWidth, height: threadgroupHeight, depth: 1)
                
                // Calculating the number of threadgroups per grid dimension
                let threadgroupsPerGrid = MTLSize(
                        width: (texture.width + threadgroupWidth - 1) / threadgroupWidth,
                        height: (texture.height + threadgroupHeight - 1) / threadgroupHeight,
                        depth: 1
                )
                
                computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                
                return outputTexture
        }
}

