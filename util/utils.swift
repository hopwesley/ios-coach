//
//  utils.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/7.
//

import MetalKit
import simd


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


func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

func saveRawDataToFile<T: Numeric & Codable>(fileName: String, buffer: MTLBuffer, width: Int, height: Int, type: T.Type) {
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
        
        dataToTmpFile(fileName: fileName, jsonData: jsonData)
}

func saveHistogramAsJSON(histogram: [MTLBuffer], fileName: String) {
        var histogramData = [[Float]]()
        
        for buffer in histogram {
                let length = buffer.length / MemoryLayout<Float>.size
                let pointer = buffer.contents().bindMemory(to: Float.self, capacity: length)
                let array = Array(UnsafeBufferPointer(start: pointer, count: length))
                histogramData.append(array)
        }
        guard let jsonData = try? JSONEncoder().encode(histogramData) else {
                print("Error encoding gray buffer to JSON")
                return
        }
        
        dataToTmpFile(fileName: fileName, jsonData: jsonData)
}

func dataToTmpFile(fileName:String, jsonData:Data){
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        do {
                try jsonData.write(to: fileURL, options: .atomic)
                print("Gray buffer saved to file: \(fileURL)")
        } catch {
                print("Error saving gray buffer to file: \(error)")
        }
}


func saveRawDataToFileWithDepth<T: Numeric & Codable>(fileName: String, buffer: MTLBuffer, width: Int, height: Int, depth: Int, type: T.Type) {
        let data = buffer.contents()
        let dataLength = width * height * depth
        let dataPointer = data.bindMemory(to: T.self, capacity: dataLength)
        
        // 将一维数组转换为三维数组
        var values = [[[T]]](repeating: [[T]](repeating: [T](repeating: 0 as T, count: depth), count: width), count: height)
        
        for y in 0..<height {
                for x in 0..<width {
                        for z in 0..<depth {
                                values[y][x][z] = dataPointer[(y * width * depth) + (x * depth) + z]
                        }
                }
        }
        
        // 将三维数组转换为 JSON 数据
        guard let jsonData = try? JSONEncoder().encode(values) else {
                print("Error encoding buffer to JSON")
                return
        }
        
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        do {
                try jsonData.write(to: fileURL, options: .atomic)
                print("Buffer saved to file: \(fileURL)")
        } catch {
                print("Error saving buffer to file: \(error)")
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


func deleteFile(at url: URL) {
        let fileManager = FileManager.default
        do {
                try fileManager.removeItem(at: url)
                print("Temporary file deleted: \(url)")
        } catch {
                print("Error deleting temporary file: \(error.localizedDescription)")
        }
}

func clearTemporaryDirectory() {
        Task {
                let fileManager = FileManager.default
                let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                
                do {
                        let tempDirectoryContents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil, options: [])
                        for file in tempDirectoryContents {
                                try fileManager.removeItem(at: file)
                        }
                        print("Temporary directory cleared successfully.")
                } catch {
                        print("Failed to clear temporary directory: \(error)")
                }
        }
}

enum ASError: Error {
        case noValidVideoTrack
        case videoTooLong
        case failedToLoadDuration
        case readVideoDataFailed
        case gpuBufferErr
        case gpuEncoderErr
        case gpuDeviceErr
        case shaderLoadErr
        case cipherErr
}

let constMaxVideoLen = 20.0
extension ASError: LocalizedError {
        var errorDescription: String? {
                switch self {
                case .noValidVideoTrack:
                        return NSLocalizedString("No valid video track was found in the provided URL.", comment: "")
                case .failedToLoadDuration:
                        return NSLocalizedString("Failed to load the duration of the video.", comment: "")
                case .videoTooLong:
                        return NSLocalizedString("Video should be shorter than \(constMaxVideoLen) seconds", comment: "")
                case .readVideoDataFailed:
                        return NSLocalizedString("Failed to read video buffer", comment: "")
                case .gpuBufferErr:
                        return NSLocalizedString("Failed to malloc gpu buffer", comment: "")
                case .gpuEncoderErr:
                        return NSLocalizedString("Failed to create gpu encoder", comment: "")
                case .gpuDeviceErr:
                        return NSLocalizedString("Gpu invalid", comment: "")
                case .shaderLoadErr:
                        return NSLocalizedString("Shader load failed", comment: "")
                case .cipherErr:
                        return NSLocalizedString("Align video and cipher failed", comment: "")
                }
        }
}


func findMinMax(buffer: MTLBuffer, length: Int) -> (minVal: Float, maxVal: Float) {
        let data = buffer.contents().bindMemory(to: Float.self, capacity: length)
        var minVal = data[0]
        var maxVal = data[0]
        
        for i in 0..<length {
                let val = data[i]
                if val > maxVal {
                        maxVal = val
                }
                if val < minVal {
                        minVal = val
                }
        }
        
        // 确保 maxVal 不为 0，以避免除以 0 的情况
        if maxVal == 0 {
                maxVal = 1
        }
        
        return (minVal, maxVal)
}
