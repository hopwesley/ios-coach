//
//  utils.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/7.
//

import PhotosUI
import SwiftUI

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
