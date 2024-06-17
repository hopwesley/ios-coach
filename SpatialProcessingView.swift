import SwiftUI
import _AVKit_SwiftUI
import PhotosUI

struct SpatialProcessingView: View {
    @ObservedObject var viewModel: SpatialGradient
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
        }
    }
}
