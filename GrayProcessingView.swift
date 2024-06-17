//
//  GrayProcessingView.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/17.
//

import SwiftUI

struct GrayProcessingView: View {
        @ObservedObject var viewModel: GrayConverter
        @State private var showImagePicker = false
        
        var body: some View {
                VStack {
                        if let grayscaleImage = viewModel.grayscaleImage {
                                Image(uiImage: grayscaleImage)
                                        .resizable()
                                        .frame(width: grayscaleImage.size.width, height: grayscaleImage.size.height)
                        }
                }
        }
}
