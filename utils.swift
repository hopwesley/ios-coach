//
//  utils.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/7.
//

import PhotosUI
import SwiftUI
import MetalKit

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
                                        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                                        let newFileName = UUID().uuidString + ".mp4"
                                        let newURL = tempDirectory.appendingPathComponent(newFileName)
                                        
                                        do {
                                                try fileManager.copyItem(at: url, to: newURL)
                                                DispatchQueue.main.async {
                                                        self.parent.videoPicked(newURL)
                                                }
                                        } catch {
                                                print("Error copying file to temporary directory: \(error.localizedDescription)")
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


func getPixelDataFromTexture(texture: MTLTexture) -> [UInt8]? {
        let width = texture.width
        let height = texture.height
        let pixelByteCount = 4 * width * height
        var rawData = [UInt8](repeating: 0, count: pixelByteCount)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&rawData, bytesPerRow: 4 * width, from: region, mipmapLevel: 0)
        
        return rawData
}


func extractPixelData(ciImage: CIImage, context: CIContext) -> [UInt8]? {
        // 将CIImage转换为CGImage
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                print("Unable to create CGImage from CIImage")
                return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        // 创建一个位图上下文
        guard let bitmapContext = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                print("Unable to create bitmap context")
                return nil
        }
        
        // 绘制CGImage到位图上下文
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return rawData
}

func textureSignleChannelToUIImage(texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * MemoryLayout<UInt8>.size
        var imageBytes = [UInt8](repeating: 0, count: rowBytes * height)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&imageBytes, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let bitsPerComponent = 8
        let bitsPerPixel = 8
        
        guard let providerRef = CGDataProvider(data: NSData(bytes: &imageBytes, length: imageBytes.count)) else {
                return nil
        }
        
        guard let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: providerRef,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
        ) else {
                return nil
        }
        
        return UIImage(cgImage: cgImage)
}


func textureToUIImage(texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        var imageBytes = [UInt8](repeating: 0, count: rowBytes * height)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&imageBytes, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        
        guard let providerRef = CGDataProvider(data: NSData(bytes: &imageBytes, length: imageBytes.count)) else {
                print("Failed to create CGDataProvider.")
                return nil
        }
        let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: providerRef,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
        )
        
        return UIImage(cgImage: cgImage!)
}

func convertToGrayscale(device: MTLDevice, commandQueue:MTLCommandQueue,
                        computePipelineState:MTLComputePipelineState,
                        from videoFrame: CVPixelBuffer) -> MTLTexture? {
        // Create a texture descriptor for the input texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: CVPixelBufferGetWidth(videoFrame),
                height: CVPixelBufferGetHeight(videoFrame),
                mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        let inputTexture = device.makeTexture(descriptor: textureDescriptor)
        
        let ciImage = CIImage(cvPixelBuffer: videoFrame)
        let context = CIContext(mtlDevice: device)
        context.render(ciImage, to: inputTexture!, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        // Create an output texture
        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: inputTexture!.width,
                height: inputTexture!.height,
                mipmapped: false
        )
        outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)
        
        // Create a command buffer and a compute command encoder
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(inputTexture, index: 0)
        computeEncoder.setTexture(outputTexture, index: 1)
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake(
                (inputTexture!.width + threadGroupSize.width - 1) / threadGroupSize.width,
                (inputTexture!.height + threadGroupSize.height - 1) / threadGroupSize.height,
                1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Get the grayscale image from the output texture
        return outputTexture
}

func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
}


func computeSpatialGradient(device: MTLDevice, commandQueue:MTLCommandQueue,
                            gradientPipelineState:MTLComputePipelineState,
                            for grayTexture: MTLTexture) -> ([Float], [Float])? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Failed to create command buffer.")
                return nil
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create compute encoder.")
                return nil
        }
        
        let width = grayTexture.width
        let height = grayTexture.height
        let size = width * height
        
        let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Float>.size, options: .storageModeShared)!
        let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        computeEncoder.setComputePipelineState(gradientPipelineState)
        computeEncoder.setTexture(grayTexture, index: 0)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 1)
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake(
                (width + threadGroupSize.width - 1) / threadGroupSize.width,
                (height + threadGroupSize.height - 1) / threadGroupSize.height,
                1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let gradientXPointer = gradientXBuffer.contents().bindMemory(to: Float.self, capacity: size)
        let gradientYPointer = gradientYBuffer.contents().bindMemory(to: Float.self, capacity: size)
        
        let gradientXArray = Array(UnsafeBufferPointer(start: gradientXPointer, count: size))
        let gradientYArray = Array(UnsafeBufferPointer(start: gradientYPointer, count: size))
        
        return (gradientXArray, gradientYArray)
}


func createTextureFromGradient(device: MTLDevice, width: Int, height: Int, gradient: [Float]) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float, // 单通道浮点纹理
                width: width,
                height: height,
                mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                print("Failed to create texture.")
                return nil
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        let bytesPerRow = MemoryLayout<Float>.size * width
        texture.replace(region: region, mipmapLevel: 0, withBytes: gradient, bytesPerRow: bytesPerRow)
        
        return texture
}


func normalizeGradient(_ gradient: [Float], width: Int, height: Int) -> [Float] {
        var normalizedGradient = [Float](repeating: 0, count: width * height)
        
        // 找到梯度数据的最小值和最大值
        let minVal = gradient.min() ?? 0
        let maxVal = gradient.max() ?? 1
        
        // 规范化梯度数据
        for i in 0..<gradient.count {
                normalizedGradient[i] = (gradient[i] - minVal) / (maxVal - minVal)
        }
        
        return normalizedGradient
}


func createTextureFromNormalizedGradient(device: MTLDevice, width: Int, height: Int, normalizedGradient: [Float]) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float, // 单通道浮点纹理
                width: width,
                height: height,
                mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                print("Failed to create texture.")
                return nil
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        let bytesPerRow = MemoryLayout<Float>.size * width
        texture.replace(region: region, mipmapLevel: 0, withBytes: normalizedGradient, bytesPerRow: bytesPerRow)
        
        return texture
}


func computeGrayscaleAndConvertToImage(device: MTLDevice, commandQueue: MTLCommandQueue,
                                       grayPipelineState: MTLComputePipelineState,
                                       from videoFrame: CVPixelBuffer) -> MTLBuffer? {
        // Create a texture descriptor for the input texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: CVPixelBufferGetWidth(videoFrame),
                height: CVPixelBufferGetHeight(videoFrame),
                mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let inputTexture = device.makeTexture(descriptor: textureDescriptor) else {
                print("Error: Failed to create input texture")
                return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: videoFrame)
        let context = CIContext(mtlDevice: device)
        context.render(ciImage, to: inputTexture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let width = inputTexture.width
        let height = inputTexture.height
        let size = width * height
        
        // Create buffer to store grayscale values
        guard let grayBuffer = device.makeBuffer(length: size * MemoryLayout<UInt8>.size, options: .storageModeShared) else {
                print("Error: Failed to create gray buffer")
                return nil
        }
        
        // Create command buffer and compute encoder for grayscale conversion
        guard let grayCommandBuffer = commandQueue.makeCommandBuffer(),
              let grayComputeEncoder = grayCommandBuffer.makeComputeCommandEncoder() else {
                print("Error: Failed to create command buffer or compute encoder")
                return nil
        }
        
        grayComputeEncoder.setComputePipelineState(grayPipelineState)
        grayComputeEncoder.setTexture(inputTexture, index: 0)
        grayComputeEncoder.setBuffer(grayBuffer, offset: 0, index: 0)
        
        let threadGroupSize = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake(
                (width + threadGroupSize.width - 1) / threadGroupSize.width,
                (height + threadGroupSize.height - 1) / threadGroupSize.height,
                1
        )
        
        grayComputeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        grayComputeEncoder.endEncoding()
        grayCommandBuffer.commit()
        grayCommandBuffer.waitUntilCompleted()
        
        // Convert gray buffer to UIImage
        return grayBuffer
}

func grayBufferToUIImage(buffer: MTLBuffer, width: Int, height: Int) -> UIImage? {
        let data = buffer.contents()
        let dataLength = width * height
        let dataPointer = data.bindMemory(to: UInt8.self, capacity: dataLength)
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let bitsPerComponent = 8
        let bitsPerPixel = 8
        let bytesPerRow = width
        
        guard let providerRef = CGDataProvider(data: NSData(bytes: dataPointer, length: dataLength) as CFData) else {
                return nil
        }
        
        guard let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: providerRef,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
        ) else {
                return nil
        }
        
        return UIImage(cgImage: cgImage)
}

func saveGrayBufferToFile(buffer: MTLBuffer, width: Int, height: Int) {
        let data = buffer.contents()
        let dataLength = width * height
        let dataPointer = data.bindMemory(to: UInt8.self, capacity: dataLength)
        
        // 将一维数组转换为二维数组
        var grayValues = [[UInt8]](repeating: [UInt8](repeating: 0, count: width), count: height)
        for y in 0..<height {
                for x in 0..<width {
                        grayValues[y][x] = dataPointer[y * width + x]
                }
        }
        
        // 将二维数组转换为 JSON 数据
        guard let jsonData = try? JSONEncoder().encode(grayValues) else {
                print("Error encoding gray buffer to JSON")
                return
        }
        
        // 将 JSON 数据保存到文件
        let fileName = "grayBuffer.json"
        if let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentDirectory.appendingPathComponent(fileName)
                do {
                        try jsonData.write(to: fileURL, options: .atomic)
                        print("Gray buffer saved to file: \(fileURL)")
                } catch {
                        print("Error saving gray buffer to file: \(error)")
                }
        }
}
