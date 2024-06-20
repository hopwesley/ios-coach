//
//  QuantizeProcessingView.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/19.
//

import SwiftUI

struct QuantizeProcessingView: View {
//        @ObservedObject var viewModel: QuantizeGradients
        @ObservedObject var viewModel: DescriptorProc
        @State private var showImagePicker = false
        
        var body: some View {
                VStack {
                        if let grayscaleImage = viewModel.grayscaleImage {
                                Image(uiImage: grayscaleImage)
                                        .resizable()
                                        .frame(width: grayscaleImage.size.width, height: grayscaleImage.size.height)
                        }
                        
                        if let gradientXImage = viewModel.gradientXImage {
                                Image(uiImage: gradientXImage)
                                        .resizable()
                                        .frame(width: gradientXImage.size.width, height: gradientXImage.size.height)
                        }
                        
                        if let gradientYImage = viewModel.gradientYImage {
                                Image(uiImage: gradientYImage)
                                        .resizable()
                                        .frame(width: gradientYImage.size.width, height: gradientYImage.size.height)
                        }
                        
                        if let gradientTImage = viewModel.gradientTImage {
                                Image(uiImage: gradientTImage)
                                        .resizable()
                                        .frame(width: gradientTImage.size.width, height: gradientTImage.size.height)
                        }
                }
        }
}
