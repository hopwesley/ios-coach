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



func textureToImage(texture: MTLTexture) -> UIImage? {
        guard let ciImage = CIImage(mtlTexture: texture, options: nil) else {
                print("Unable to create CIImage from texture")
                return nil
        }
        
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                print("Unable to create CGImage from CIImage")
                return nil
        }
        
        return UIImage(cgImage: cgImage)
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
