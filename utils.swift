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

func showSpatialGradientAnswer(device: MTLDevice, commandQueue: MTLCommandQueue,
                               gradientPipelineState: MTLComputePipelineState,
                               grayBuffer: MTLBuffer, width: Int, height: Int) -> (MTLBuffer, MTLBuffer)? {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                print("Failed to create command buffer.")
                return nil
        }
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create compute encoder.")
                return nil
        }
        
        let size = width * height
        
        let gradientXBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared)!
        let gradientYBuffer = device.makeBuffer(length: size * MemoryLayout<Int16>.size, options: .storageModeShared)!
        
        computeEncoder.setComputePipelineState(gradientPipelineState)
        computeEncoder.setBuffer(grayBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(gradientXBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(gradientYBuffer, offset: 0, index: 2)
        var w = width
        var h = height
        computeEncoder.setBytes(&w, length: MemoryLayout<uint>.size, index: 3)
        computeEncoder.setBytes(&h, length: MemoryLayout<uint>.size, index: 4)
        
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                   depth: 1)
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return (gradientXBuffer, gradientYBuffer)
}


func computeGrayscale(device: MTLDevice, commandQueue: MTLCommandQueue,
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

func saveGrayBufferToFile<T: Numeric & Codable>(fileName: String, buffer: MTLBuffer, width: Int, height: Int, type: T.Type) {
        let data = buffer.contents()
        let dataLength = width * height
        let dataPointer = data.bindMemory(to: T.self, capacity: dataLength)
        
        // 将一维数组转换为二维数组
        var grayValues = [[T]](repeating: [T](repeating: 0 as T, count: width), count: height)
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


func mtlBufferToFloat(gradientBuffer:MTLBuffer, size:Int)->[Float]{
        let bufferPointer = gradientBuffer.contents().bindMemory(to: Float.self, capacity: size)
        return Array(UnsafeBufferPointer(start: bufferPointer, count: size))
}


func convertInt16ToUInt8(buffer: MTLBuffer, width: Int, height: Int) -> MTLBuffer? {
        let dataLength = width * height
        let data = buffer.contents()
        let dataPointer = data.bindMemory(to: Int16.self, capacity: dataLength)
        
        // Step 1: Calculate min and max values
        var minVal = Int16.max
        var maxVal = Int16.min
        
        for i in 0..<dataLength {
                let value = dataPointer[i]
                if value < minVal {
                        minVal = value
                }
                if value > maxVal {
                        maxVal = value
                }
        }
        
        // Step 2: Calculate alpha and beta
        let midVal = (Float(minVal) + Float(maxVal)) / 2.0
        let alpha = 255.0 / (Float(maxVal) - Float(minVal))
        let beta = 128.0 - midVal * alpha
        
        // Step 3: Create new buffer for uint8 data
        let uint8Buffer = buffer.device.makeBuffer(length: dataLength * MemoryLayout<UInt8>.size, options: .storageModeShared)!
        let uint8Pointer = uint8Buffer.contents().bindMemory(to: UInt8.self, capacity: dataLength)
        
        // Step 4: Convert int16 data to uint8 data
        for i in 0..<dataLength {
                let int16Value = Float(dataPointer[i])
                let floatResult = int16Value * alpha + beta
                let uint8Value = UInt8(min(max(floatResult, 0), 255))  // Clamp the value between 0 and 255
                uint8Pointer[i] = uint8Value
        }
        
        return uint8Buffer
}

