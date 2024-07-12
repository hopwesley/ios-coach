import SwiftUI
import AVKit

struct ManualAlignView: View {
        @State var urlA: URL
        @State var urlB: URL
        
        // 为每个视频定义开始和结束时间
        @State private var startTimeA: Double = 0
        @State private var endTimeA: Double = 60
        @State private var startTimeB: Double = 0
        @State private var endTimeB: Double = 60
        
        // 假设两个视频的总时长均为60秒
        let videoLength: Double = 60
        
        var body: some View {
                
                ScrollView {
                        VStack {
                                VideoPlayer(player: AVPlayer(url: urlA))
                                        .frame(height: 200)
                                videoControlSection(startTime: $startTimeA, endTime: $endTimeA, label: "A")
                                
                                VideoPlayer(player: AVPlayer(url: urlB))
                                        .frame(height: 200)
                                videoControlSection(startTime: $startTimeB, endTime: $endTimeB, label: "B")
                                
                                Button("Save") {
                                        print("Video A - Start Time: \(startTimeA)s, End Time: \(endTimeA)s")
                                        print("Video B - Start Time: \(startTimeB)s, End Time: \(endTimeB)s")
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding()
                }
        }
        
        // 为每个视频定义控制条
        private func videoControlSection(startTime: Binding<Double>, endTime: Binding<Double>, label: String) -> some View {
                VStack {
                        Text("\(label) Start Time: \(startTime.wrappedValue, specifier: "%.2f")s")
                        Slider(value: startTime, in: 0...endTime.wrappedValue, step: 1.0)
                                .padding()
                        
                        Text("\(label) End Time: \(endTime.wrappedValue, specifier: "%.2f")s")
                        Slider(value: endTime, in: startTime.wrappedValue...videoLength, step: 1.0)
                                .padding()
                }
        }
}
