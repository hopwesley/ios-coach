//
//  VideoAlignment.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/24.
//

import Foundation

import AVFoundation
import CoreImage
class VideoAlignment: ObservableObject {
        
        @Published var videoURL: URL?
        @Published var cipheredVideoUrl: URL?
        @Published var videoInfo:String?
        @Published var FrameCount:Int?
        var videoWidth:Int = 0
        var videoHeight:Int = 0
        var pixelSize:Int = 0
        var numBlocks:Int = 0
        var sideOfBlock:Int = 0
        var numBlocksX:Int = 0
        
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var grayAndDiffPipe: MTLComputePipelineState!
        var spaceGradientPipe: MTLComputePipelineState!
        var blockHistogramPipe:MTLComputePipelineState!
        var frameSumGradientPipe:MTLComputePipelineState!
        var textureDescriptor:MTLTextureDescriptor!
        
        var grayBufferPre:MTLBuffer?
        var grayBufferCur:MTLBuffer?
        var gradientBufferX:MTLBuffer?
        var gradientBufferY:MTLBuffer?
        var gradientBufferT:MTLBuffer?
        var avgGradientOfBlock:MTLBuffer?
        var projectionBuf:MTLBuffer?
        
        var pixelThreadGrpSize:MTLSize = MTLSize(width: PixelThreadWidth,
                                                 height: PixelThreadHeight,
                                                 depth: 1)
        var pixelThreadGrpNo:MTLSize?
        var blockThreadGrpSize:MTLSize?
        var blockThreadGrpNo:MTLSize?
        var  summerGroupSize:MTLSize = MTLSize(width: ThreadSizeForParallelSum, height: 1, depth: 1)
        var summerGroups:MTLSize = MTLSize(width: HistogramSize, height: 1, depth: 1)
        
        
        func removeVideo(){
                if let url = self.videoURL{
                        deleteFile(at: url)
                }
                self.videoURL = nil
                self.FrameCount = nil
        }
        
        func prepareVideoInBackground(url:URL){
                DispatchQueue.main.async {
                        self.videoURL = url
                }
                Task{
                        async let parseResult: () = self.parseVideo(url: url)
                        async let gpuInitResult: () = self.initGpuAndMemory()
                        
                        do{
                                try await parseResult
                                try await gpuInitResult
                        }catch{
                                DispatchQueue.main.async {
                                        self.videoInfo =  error.localizedDescription
                                }
                        }
                }
        }
        
        func parseVideo(url:URL) async throws{
                
                let asset = AVAsset(url: url)
                let d = try await asset.load(.duration)
                let duration = CMTimeGetSeconds(d)
                if duration > constMaxVideoLen{
                        throw ASError.videoTooLong
                }
                
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        throw ASError.noValidVideoTrack
                }
                let videoSize = try await videoTrack.load(.naturalSize)
                self.videoWidth = Int(videoSize.width)
                self.videoHeight = Int(videoSize.height)
                self.pixelSize = self.videoWidth * self.videoHeight
                
                let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)//.nominalFrameRate
                
                DispatchQueue.main.async {
                        self.videoInfo =  "width(\(self.videoWidth)) height(\(self.videoHeight)) duration(\(duration) )seconds"
                        self.FrameCount = Int(duration * Double(nominalFrameRate))
                }
                
                self.textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba8Unorm,
                        width: self.videoWidth,
                        height: self.videoHeight,
                        mipmapped: false
                )
                textureDescriptor.usage = [.shaderRead, .shaderWrite]
        }
        
        private func pixelBufferToTexture(_ sbuf: CMSampleBuffer)->MTLTexture?{
                guard let videoFrame = CMSampleBufferGetImageBuffer(sbuf) else{
                        return nil
                }
                guard let inputTexture = device.makeTexture(descriptor: textureDescriptor) else {
                        print("Error: Failed to create input texture")
                        return nil
                }
                
                let ciImage = CIImage(cvPixelBuffer: videoFrame)
                let context = CIContext(mtlDevice: device)
                context.render(ciImage, to: inputTexture, commandBuffer: nil, bounds: ciImage.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                
                return inputTexture
        }
        
        func AlignVideo(completion: @escaping (Result<(MTLBuffer, Int), Error>) -> Void) {
                Task {
                        do {
                                try prepareGpuResource(sideOfDesc: SideSizeOfLevelZero)
                                let result = try await calculateFrameQuantizedAverageGradient()
                                DispatchQueue.main.async {
                                        completion(.success(result))
                                }
                        } catch {
                                DispatchQueue.main.async {
                                        completion(.failure(error))
                                }
                        }
                }
        }
        
        private func calculateFrameQuantizedAverageGradient() async throws->(MTLBuffer, Int){
                guard let url = self.videoURL else{
                        throw ASError.readVideoDataFailed
                }
                
                let asset = AVAsset(url: url)
                let reader = try AVAssetReader(asset: asset)
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        throw ASError.noValidVideoTrack
                }
                
                let trackReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                        (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
                ])
                reader.add(trackReaderOutput)
                reader.startReading()
                
                var preFrame:MTLTexture? = nil
                let maxFrameCount = self.FrameCount! + 2
                
                let bufferSize = maxFrameCount * 10 * MemoryLayout<Float>.stride
                let allFrameSumGradient = device.makeBuffer(length: bufferSize, options: .storageModeShared)!
                var currentOffset = 0
                var frameCount = 0
                
                while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
                        guard  let frame = pixelBufferToTexture(sampleBuffer) else{
                                throw ASError.readVideoDataFailed
                        }
                        if preFrame == nil{
                                preFrame = frame
                                continue
                        }
                        let sumGradient =  try procFrameData(rawImgPre: preFrame!, rawImgCur: frame)
                        preFrame = frame
                        //                        allFrameSumGradient.append(sumGradient)
                        memcpy(allFrameSumGradient.contents() + currentOffset, sumGradient.contents(), 10 * MemoryLayout<Float>.stride)
                        currentOffset += 10 * MemoryLayout<Float>.stride
                        frameCount += 1
#if AlignJsonData
                        let sumPointer = sumGradient.contents().assumingMemoryBound(to: Float.self)
                        if sumPointer.pointee == 0{
                                debugBuffer(sumGradient: sumGradient)
                        }
#endif
                }
                print("frame sum gradient size:", frameCount)
                reader.cancelReading()
                return (allFrameSumGradient, frameCount)
        }
        
        func initGpuAndMemory() throws{
                device = MTLCreateSystemDefaultDevice()
                commandQueue = device.makeCommandQueue()
                
                guard let library = device.makeDefaultLibrary() else{
                        throw ASError.gpuDeviceErr
                }
                
                guard let grayAndDiff = library.makeFunction(name: "grayAndTimeDiff"),
                      let spaceGradientFun = library.makeFunction(name: "spaceGradient"),
                      let quantizeGradientFun = library.makeFunction(name: "quantizeAvgerageGradientOfBlock"),
                      let sumFunc = library.makeFunction(name: "sumQuantizedGradients") else{
                        throw ASError.shaderLoadErr
                }
                grayAndDiffPipe = try device.makeComputePipelineState(function: grayAndDiff)
                spaceGradientPipe = try device.makeComputePipelineState(function: spaceGradientFun)
                blockHistogramPipe = try device.makeComputePipelineState(function: quantizeGradientFun)
                frameSumGradientPipe = try device.makeComputePipelineState(function: sumFunc)
        }
        
        func prepareGpuResource(sideOfDesc:Int) throws{
                
                let blockSideOneDesc = DescriptorParam_M * DescriptorParam_m
                let blockSize = sideOfDesc / blockSideOneDesc
                self.numBlocksX = (self.videoWidth + blockSize - 1) / blockSize
                let numBlocksY = (self.videoHeight + blockSize - 1) / blockSize
                self.numBlocks = self.numBlocksX * numBlocksY
                self.sideOfBlock = blockSize
                let histogramLen = numBlocks * HistogramSize * MemoryLayout<Float>.stride
                guard let grayBufferA = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let grayBufferB = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let grayBufferT = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.stride, options: .storageModeShared),
                      let grayBufferX = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared),
                      let grayBufferY = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.stride, options: .storageModeShared),
                      let avgGradientAllBlock = device.makeBuffer(length: histogramLen, options: .storageModeShared),
                      let pBuffer = device.makeBuffer(bytes: normalizedP,
                                                      length: MemoryLayout<SIMD3<Float>>.stride * normalizedP.count, options: .storageModeShared) else{
                        throw ASError.gpuBufferErr
                }
                
                self.grayBufferPre = grayBufferA
                self.grayBufferCur = grayBufferB
                self.gradientBufferT = grayBufferT
                self.gradientBufferX = grayBufferX
                self.gradientBufferY = grayBufferY
                self.avgGradientOfBlock = avgGradientAllBlock
                self.projectionBuf = pBuffer
                
                pixelThreadGrpNo = MTLSize(width: (self.videoWidth + PixelThreadWidth - 1) / PixelThreadWidth,
                                           height: (self.videoHeight + PixelThreadHeight - 1) / PixelThreadHeight,
                                           depth: 1)
                
                blockThreadGrpSize =  MTLSize(width: blockSideOneDesc,
                                              height: blockSideOneDesc,
                                              depth: 1)
                blockThreadGrpNo = MTLSize(
                        width: (numBlocksX + blockSideOneDesc - 1) / blockSideOneDesc,
                        height: (numBlocksY + blockSideOneDesc - 1) / blockSideOneDesc,
                        depth: 1
                )
        }
        
        func resetBuffer(){
                memset(grayBufferPre?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(grayBufferCur?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferT?.contents(), 0, self.pixelSize * MemoryLayout<UInt8>.stride)
                memset(gradientBufferX?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(gradientBufferY?.contents(), 0, self.pixelSize * MemoryLayout<Int16>.stride)
                memset(avgGradientOfBlock?.contents(), 0, numBlocks * HistogramSize * MemoryLayout<Float>.stride)
        }
        
        func procFrameData(rawImgPre: MTLTexture, rawImgCur: MTLTexture) throws -> MTLBuffer{
                
                resetBuffer()
                
                let bufferMemSize = HistogramSize * MemoryLayout<Float>.size
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let sumBuffer = device.makeBuffer(length:bufferMemSize , options: .storageModeShared) else{
                        throw ASError.gpuBufferErr
                }
                memset(sumBuffer.contents(), 0, bufferMemSize)
                try encodeGray(rawImgPre: rawImgPre, rawImgCur: rawImgCur, commandBuffer: commandBuffer)
                try encodeSpaceGradient(commandBuffer: commandBuffer)
                try encodeQuantizer(commandBuffer: commandBuffer)
                try encodeSummer(sumGradient:sumBuffer, commandBuffer:commandBuffer)
                
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                
                return sumBuffer
        }
        
        func encodeGray(rawImgPre: MTLTexture, rawImgCur: MTLTexture, commandBuffer:MTLCommandBuffer) throws{
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                coder.setComputePipelineState(self.grayAndDiffPipe)
                coder.setTexture(rawImgPre, index: 0)
                coder.setTexture(rawImgCur, index: 1)
                coder.setBuffer(grayBufferPre, offset: 0, index: 0)
                coder.setBuffer(grayBufferCur, offset: 0, index: 1)
                coder.setBuffer(gradientBufferT, offset: 0, index: 2)
                coder.dispatchThreadgroups(pixelThreadGrpNo!,
                                           threadsPerThreadgroup: pixelThreadGrpSize)
                coder.endEncoding()
        }
        
        func encodeSpaceGradient(commandBuffer:MTLCommandBuffer) throws{
                
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(spaceGradientPipe)
                coder.setBuffer(grayBufferCur, offset: 0, index: 0)
                coder.setBuffer(gradientBufferX, offset: 0, index: 1)
                coder.setBuffer(gradientBufferY, offset: 0, index: 2)
                var w = self.videoWidth
                var h = self.videoHeight
                coder.setBytes(&w, length: MemoryLayout<Int>.size, index: 3)
                coder.setBytes(&h, length: MemoryLayout<Int>.size, index: 4)
                
                coder.dispatchThreadgroups(pixelThreadGrpNo!,
                                           threadsPerThreadgroup: pixelThreadGrpSize)
                coder.endEncoding()
        }
        
        func encodeQuantizer(commandBuffer:MTLCommandBuffer) throws{
                
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(self.blockHistogramPipe)
                
                coder.setBuffer(gradientBufferX, offset: 0, index: 0)
                coder.setBuffer(gradientBufferY, offset: 0, index: 1)
                coder.setBuffer(gradientBufferT, offset: 0, index: 2)
                coder.setBuffer(avgGradientOfBlock, offset: 0, index: 3)
                coder.setBuffer(self.projectionBuf, offset: 0, index: 4)
                
                coder.setBytes(&self.videoWidth, length: MemoryLayout<Int>.size, index: 5)
                coder.setBytes(&self.videoHeight, length: MemoryLayout<Int>.size, index: 6)
                coder.setBytes(&self.sideOfBlock, length: MemoryLayout<Int>.size, index: 7)
                coder.setBytes(&numBlocksX, length: MemoryLayout<Int>.size, index: 8)
                
                coder.dispatchThreadgroups(blockThreadGrpNo!,
                                           threadsPerThreadgroup: blockThreadGrpSize!)
                coder.endEncoding()
        }
        
        func encodeSummer(sumGradient:MTLBuffer, commandBuffer:MTLCommandBuffer) throws{
                
                guard let coder = commandBuffer.makeComputeCommandEncoder()else{
                        throw ASError.gpuEncoderErr
                }
                
                coder.setComputePipelineState(self.frameSumGradientPipe)
                coder.setBuffer(avgGradientOfBlock, offset: 0, index: 0)
                coder.setBuffer(sumGradient, offset: 0, index: 1)
                coder.setBytes(&self.numBlocks, length: MemoryLayout<UInt>.size, index: 2)
                var threadGroupSize: UInt = UInt(ThreadSizeForParallelSum)
                coder.setBytes(&threadGroupSize, length: MemoryLayout<UInt>.size, index: 3)
                coder.setThreadgroupMemoryLength(MemoryLayout<Float>.stride * ThreadSizeForParallelSum, index: 0) // 分配线程组内存
                
                coder.dispatchThreadgroups(summerGroups,threadsPerThreadgroup: summerGroupSize)
                coder.endEncoding()
        }
#if AlignJsonData
        var counter:Int = 0
        func debugBuffer(sumGradient:MTLBuffer){
                let w = self.videoWidth
                let h = self.videoHeight
                saveRawDataToFile(fileName: "gpu_grayBufferA_\(counter).json", buffer: grayBufferCur!, width: w, height: h, type: UInt8.self)
                saveRawDataToFile(fileName: "gpu_grayBufferB_\(counter).json", buffer: grayBufferPre!, width: w, height: h, type: UInt8.self)
                saveRawDataToFile(fileName: "gpu_gradientXBuffer_\(counter).json", buffer: gradientBufferX!, width: w, height: h, type: Int16.self)
                saveRawDataToFile(fileName: "gpu_gradientYBuffer_\(counter).json", buffer: gradientBufferY!, width: w, height: h, type: Int16.self)
                saveRawDataToFile(fileName: "gpu_gradientTBuffer_\(counter).json", buffer: gradientBufferT!, width: w, height: h, type: UInt8.self)
                
                let numBlocksY = (self.videoHeight + self.sideOfBlock - 1) / self.sideOfBlock
                saveRawDataToFileWithDepth(fileName: "gpu_frame_quantity_\(self.sideOfBlock)_\(counter).json", buffer: avgGradientOfBlock!,
                                           width: numBlocksX, height: numBlocksY, depth: HistogramSize, type: Float.self)
                saveRawDataToFile(fileName: "gpu_gradientSumOfOneFrame_\(counter).json", buffer: sumGradient,  width: 10, height: 1,  type: Float.self)
                counter+=1
        }
#endif
        
        func cipherVideo(offset: Int, len: Int) async throws {
                guard let videoURL = self.videoURL else {
                        throw ASError.cipherErr
                }
                
                let asset = AVAsset(url: videoURL)
                let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(videoURL.lastPathComponent + "_trimmedVideo.mp4")
                
                try? FileManager.default.removeItem(at: outputURL)
                
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        print("No valid video track found")
                        return
                }
                
                let frameRate = try await videoTrack.load(.nominalFrameRate)
                let startTime = CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(frameRate))
                let duration = CMTime(value: CMTimeValue(len), timescale: CMTimeScale(frameRate))
                
                let composition = AVMutableComposition()
                guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        print("Failed to create composition track")
                        return
                }
                
                // 应用原始视频轨道的变换
                let transform = try await videoTrack.load(.preferredTransform)
                compositionTrack.preferredTransform = transform
                
                do {
                        try compositionTrack.insertTimeRange(CMTimeRange(start: startTime, duration: duration), of: videoTrack, at: .zero)
                        
                        // 确保renderSize正确
                        let naturalSize = try await videoTrack.load(.naturalSize)
                        let transformedSize = naturalSize.applying(transform)
                        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                        
                        // 创建视频合成
                        let videoComposition = AVMutableVideoComposition()
                        videoComposition.renderSize = renderSize
                        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
                        
                        let instruction = AVMutableVideoCompositionInstruction()
                        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
                        
                        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
                        layerInstruction.setTransform(transform, at: .zero)
                        
                        instruction.layerInstructions = [layerInstruction]
                        videoComposition.instructions = [instruction]
                        
                        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                                print("Failed to create exporter")
                                return
                        }
                        
                        exporter.outputURL = outputURL
                        exporter.outputFileType = .mp4
                        exporter.videoComposition = videoComposition
                        
                        try await withCheckedThrowingContinuation { continuation in
                                exporter.exportAsynchronously {
                                        switch exporter.status {
                                        case .completed:
                                                DispatchQueue.main.async {
                                                        self.cipheredVideoUrl = outputURL
                                                        print("Video trimmed successfully", outputURL.absoluteString)
                                                }
                                                continuation.resume()
                                        case .failed:
                                                continuation.resume(throwing: exporter.error ?? NSError(domain: "Unknown error", code: -1, userInfo: nil))
                                        default:
                                                break
                                        }
                                }
                        }
                } catch {
                        print("Error during composition: \(error)")
                }
        }
        
}



func findBestAlignOffset(histoA: MTLBuffer, countA: Int, histoB: MTLBuffer, countB: Int,seqLen:Int) -> (Int, Int, Int)? {
        
        let device = MTLCreateSystemDefaultDevice()!
        let commandQueue = device.makeCommandQueue()!
        let library = device.makeDefaultLibrary()!
        let function = library.makeFunction(name: "nccOfAllFrameByHistogram")!
        let nccPipelineState = try! device.makeComputePipelineState(function: function)
        
        let weightedNCCFunction = library.makeFunction(name: "calculateWeightedNCC")!
        let weightedNccPipeline = try! device.makeComputePipelineState(function: weightedNCCFunction)
        
        // Assumes that all buffers are of the same size
        var width = countB
        var height = countA
        
        var sequenceLength = min(width, height)
        if sequenceLength < seqLen{
                sequenceLength -= 1
        }else{
                sequenceLength = seqLen
        }
        
        var weightedWidth = width - sequenceLength + 1
        var weightedHeight = height - sequenceLength + 1
        
        let nccValuesCount = width * height
        let weightedNccValuesCount = weightedWidth * weightedHeight
        
        let nccValuesBuffer = device.makeBuffer(length: nccValuesCount * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        let weightedNccValuesBuffer = device.makeBuffer(length: weightedNccValuesCount * MemoryLayout<Float>.size, options: .storageModeShared)!
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        var encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(nccPipelineState)
        encoder.setBuffer(histoA, offset: 0, index: 0)
        encoder.setBuffer(histoB, offset: 0, index: 1)
        encoder.setBuffer(nccValuesBuffer, offset: 0, index: 2)
        
        encoder.setBytes(&width, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&height, length: MemoryLayout<UInt32>.size, index: 4)
        
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        var threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                   depth: 1)
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        print("new width no:\(weightedWidth) new height no:\(weightedHeight)")
        encoder = commandBuffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(weightedNccPipeline)
        encoder.setBuffer(nccValuesBuffer, offset: 0, index: 0)
        encoder.setBuffer(weightedNccValuesBuffer, offset: 0, index: 1)
        encoder.setBytes(&weightedWidth, length: MemoryLayout<UInt32>.size, index: 2)
        encoder.setBytes(&weightedHeight, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&sequenceLength, length: MemoryLayout<UInt32>.size, index: 4)
        encoder.setBytes(&width, length: MemoryLayout<UInt32>.size, index: 5)
        
        let threadWidth = (weightedWidth + threadGroupSize.width - 1) / threadGroupSize.width
        let threadHeight = (weightedHeight + threadGroupSize.height - 1) / threadGroupSize.height
        print("thread width:\(threadWidth) thread height:\(threadHeight)")
        
        threadGroups = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        guard  let (maxValue, maxIndex) = findMaxValueInBuffer(buffer: weightedNccValuesBuffer, count: weightedNccValuesCount)  else{
                return nil
        }
        
        
        
#if AlignJsonData
        saveRawDataToFile(fileName: "gpu_frame_histogram_A.json",
                          buffer: histoA, width: 10, height: countA, type: Float.self)
        saveRawDataToFile(fileName: "gpu_frame_histogram_B.json",
                          buffer: histoB, width: 10, height: countB, type: Float.self)
        saveRawDataToFile(fileName: "gpu_ncc_a_b.json", buffer: nccValuesBuffer, width:width , height: height, type: Float.self)
        
        
        saveRawDataToFile(fileName: "gpu_ncc_weighted_sum.json",
                          buffer: weightedNccValuesBuffer, width: weightedWidth, height: weightedHeight, type: Float.self)
#endif
        
        let aIdx = maxIndex / weightedWidth
        let bIdx = maxIndex % weightedWidth
        print("aIdx=\(aIdx) bIdx=\(bIdx) val=\(maxValue) maxIdx = \(maxIndex)")
        return (aIdx, bIdx, sequenceLength)
}

func findMaxValueInBuffer(buffer: MTLBuffer, count: Int) -> (Float, Int)? {
        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: count)
        var maxValue: Float = -Float.greatestFiniteMagnitude
        var maxIndex: Int = -1
        
        for i in 0..<count {
                if pointer[i] > maxValue {
                        maxValue = pointer[i]
                        maxIndex = i
                }
        }
        
        if maxIndex == -1 {
                return nil
        } else {
                return (maxValue, maxIndex)
        }
}
