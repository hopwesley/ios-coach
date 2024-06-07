import SwiftUI
import AVFoundation
import MetalKit
import CoreImage

struct MetalView_test2: View {
    @StateObject private var viewModel = VideoProcessingViewModel4()
    
    var body: some View {
        VStack {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Text("Loading...")
            }
        }
        .onAppear {
            viewModel.processVideo()
        }
    }
}

class VideoProcessingViewModel4: ObservableObject {
    @Published var image: UIImage?
    
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var computePipelineState: MTLComputePipelineState!
    var context: CIContext!
    
    init() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        context = CIContext(mtlDevice: device)
        
        let defaultLibrary = device.makeDefaultLibrary()
        let computeFunction = defaultLibrary?.makeFunction(name: "spatial_gradient")
        computePipelineState = try! device.makeComputePipelineState(function: computeFunction!)
    }
    
    func processVideo() {
        let videoPath = Bundle.main.path(forResource: "A", ofType: "mp4")!
        let grayImages = readAllFramesAndConvertToGray(videoPath: videoPath)
        let textures = createTextures(from: grayImages)
        let gradientTextures = computeSpatialGradients(textures: textures)
        
        if let gradientTexture = gradientTextures.first {
            image = gradientTexture.toUIImage()
        }
    }
    
    func readAllFramesAndConvertToGray(videoPath: String) -> [CIImage] {
        var grayImages: [CIImage] = []
        let asset = AVAsset(url: URL(fileURLWithPath: videoPath))
        let assetReader = try! AVAssetReader(asset: asset)
        
        let videoTrack = asset.tracks(withMediaType: .video).first!
        let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        assetReader.add(trackReaderOutput)
        
        assetReader.startReading()
        while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let ciImage = CIImage(cvImageBuffer: imageBuffer)
                let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
                grayImages.append(grayscale)
            }
        }
        
        return grayImages
    }
    
    func createTextures(from ciImages: [CIImage]) -> [MTLTexture] {
        var textures: [MTLTexture] = []
        let textureLoader = MTKTextureLoader(device: device)
        
        for ciImage in ciImages {
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let textureLoaderOptions: [MTKTextureLoader.Option: Any] = [.SRGB: false]
                do {
                    let texture = try textureLoader.newTexture(cgImage: cgImage, options: textureLoaderOptions)
                    textures.append(texture)
                } catch {
                    print("Unable to create texture from image: \(error)")
                }
            }
        }
        
        return textures
    }
    
    func computeSpatialGradients(textures: [MTLTexture]) -> [MTLTexture] {
        var gradientTextures: [MTLTexture] = []
        let bufferSize = textures.first!.width * textures.first!.height * MemoryLayout<Float>.size

        for texture in textures {
            let gradientTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: texture.width, height: texture.height, mipmapped: false)
            gradientTextureDescriptor.usage = [.shaderRead, .shaderWrite]
            let gradientTexture = device.makeTexture(descriptor: gradientTextureDescriptor)
            gradientTextures.append(gradientTexture!)
            
            let outGradientXBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
            let outGradientYBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
            
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            computeEncoder.setComputePipelineState(computePipelineState)
            computeEncoder.setTexture(texture, index: 0)
            computeEncoder.setBuffer(outGradientXBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(outGradientYBuffer, offset: 0, index: 1)
            
            let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroupsPerGrid = MTLSize(width: (texture.width + 15) / 16, height: (texture.height + 15) / 16, depth: 1)
            
            computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            computeEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        return gradientTextures
    }
}

// MTLTexture 扩展，用于转换为 UIImage
extension MTLTexture {
    func toUIImage() -> UIImage? {
        let width = self.width
        let height = self.height
        let rowBytes = width
        let length = rowBytes * height
        
        var data = Data(count: length)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            self.getBytes(bytes.baseAddress!, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        
        let providerRef = CGDataProvider(data: data as CFData)!
        let colorSpaceRef = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let renderingIntent = CGColorRenderingIntent.defaultIntent
        
        if let cgImage = CGImage(width: width,
                                 height: height,
                                 bitsPerComponent: 8,
                                 bitsPerPixel: 8,
                                 bytesPerRow: rowBytes,
                                 space: colorSpaceRef,
                                 bitmapInfo: bitmapInfo,
                                 provider: providerRef,
                                 decode: nil,
                                 shouldInterpolate: true,
                                 intent: renderingIntent) {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
}
