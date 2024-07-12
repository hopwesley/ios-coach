import SwiftUI
import AVKit

struct ManualAlignView: View {
        @State var urlA: URL
        @State var urlB: URL
        
        @State private var playerA: AVPlayer?
        @State private var playerB: AVPlayer?
        
        @State private var startTimeA: Double = 0
        @State private var endTimeA: Double = 10
        @State private var startTimeB: Double = 0
        @State private var endTimeB: Double = 10
        
        @State private var videoLengthA: Double = 10
        @State private var videoLengthB: Double = 10
        
        init(urlA: URL, urlB: URL) {
                self.urlA = urlA
                self.urlB = urlB
                _playerA = State(initialValue: AVPlayer(url: urlA))
                _playerB = State(initialValue: AVPlayer(url: urlB))
        }
        
        @MainActor
        private func loadVideoDurations() async {
                do {
                        let assetA = AVURLAsset(url: urlA)
                        let assetB = AVURLAsset(url: urlB)
                        let durationA = try await assetA.load(.duration)
                        let durationB = try await assetB.load(.duration)
                        videoLengthA = CMTimeGetSeconds(durationA)
                        videoLengthB = CMTimeGetSeconds(durationB)
                        endTimeA = videoLengthA
                        endTimeB = videoLengthB
                } catch {
                        print("Error loading video durations: \(error)")
                }
        }
        
        var body: some View {
                VStack {
                        VideoPlayer(player: playerA).frame(height: 200)
                        Text("Start Time A: \(startTimeA, specifier: "%.2f") seconds")
                        Slider(value: Binding(
                                get: { startTimeA },
                                set: { newStartTime in
                                        startTimeA = min(newStartTime, endTimeA - 0.01)
                                }
                        ), in: 0...videoLengthA, step: 0.01)
                        Text("End Time A: \(endTimeA, specifier: "%.2f") seconds")
                        Slider(value: Binding(
                                get: { endTimeA },
                                set: { newEndTime in
                                        endTimeA = max(newEndTime, startTimeA + 0.01)
                                }
                        ), in: 0...videoLengthA, step: 0.01)
                        
                        VideoPlayer(player: playerB).frame(height: 200)
                        Text("Start Time B: \(startTimeB, specifier: "%.2f") seconds")
                        Slider(value: Binding(
                                get: { startTimeB },
                                set: { newStartTime in
                                        startTimeB = min(newStartTime, endTimeB - 0.01)
                                }
                        ), in: 0...videoLengthB, step: 0.01)
                        Text("End Time B: \(endTimeB, specifier: "%.2f") seconds")
                        Slider(value: Binding(
                                get: { endTimeB },
                                set: { newEndTime in
                                        endTimeB = max(newEndTime, startTimeB + 0.01)
                                }
                        ), in: 0...videoLengthB, step: 0.01)
                        
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
                .task {
                        await loadVideoDurations()
                }
        }
}
