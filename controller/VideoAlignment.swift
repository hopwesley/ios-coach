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
        @Published var videoInfo:String?
        
        var videoWidth:Int = 0
        var videoHeight:Int = 0
        var pixelSize:Int = 0
        var numBlocks:Int = 0
        var sideOfBlock:Int = 0
        
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
        var  summerGroupSize:MTLSize = MTLSize(width: HistorgramSize, height: 1, depth: 1)
        var summerGroups:MTLSize = MTLSize(width: 1, height: 1, depth: 1)
        
        
        func removeVideo(){
                if let url = self.videoURL{
                        deleteFile(at: url)
                }
                self.videoURL = nil
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
                DispatchQueue.main.async {
                        self.videoInfo =  "width(\(self.videoWidth)) height(\(self.videoHeight)) duration(\(duration) )seconds"
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
        
        func DebugAlignVideo(){
                
                Task{
                        do{
                                try prepareGpuResource(sideOfDesc:SideSizeOfLevelZero)
                                let _ = try await calculateFrameQuantizedAverageGradient(isDebug: true)
                        }catch{
                                DispatchQueue.main.async {
                                        self.videoInfo =  error.localizedDescription
                                }
                        }
                }
        }
        
        func AlignVideo(completion: @escaping (Result<[MTLBuffer], Error>) -> Void) {
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
        
        private func calculateFrameQuantizedAverageGradient(isDebug:Bool = false) async throws->[MTLBuffer]{
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
                
                var allFrameSumGradient:[MTLBuffer] = []
                
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
                        allFrameSumGradient.append(sumGradient)
                        let sumPointer = sumGradient.contents().assumingMemoryBound(to: Float.self)
                        if isDebug || sumPointer.pointee == 0{
                                debugBuffer(sumGradient: sumGradient)
                                if isDebug{
                                        break
                                }
                        }
                }
                
                print("frame sum gradient size:", allFrameSumGradient.count)
                return allFrameSumGradient
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
                let numBlocksX = (self.videoWidth + blockSize - 1) / blockSize
                let numBlocksY = (self.videoHeight + blockSize - 1) / blockSize
                self.numBlocks = numBlocksX * numBlocksY
                self.sideOfBlock = blockSize
                let PBufferSize = icosahedronCenterP.count * MemoryLayout<SIMD3<Float>>.stride
                
                guard let grayBufferA = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.size, options: .storageModeShared),
                      let grayBufferB = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.size, options: .storageModeShared),
                      let grayBufferT = device.makeBuffer(length: self.pixelSize * MemoryLayout<UInt8>.size, options: .storageModeShared),
                      let grayBufferX = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.size, options: .storageModeShared),
                      let grayBufferY = device.makeBuffer(length: self.pixelSize * MemoryLayout<Int16>.size, options: .storageModeShared),
                      let avgGradientAllBlock = device.makeBuffer(length: numBlocks * HistorgramSize * MemoryLayout<Float>.stride,
                                                                  options: .storageModeShared),
                      let pBuffer = device.makeBuffer(bytes: icosahedronCenterP, length: PBufferSize, options: .storageModeShared) else{
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
                memset(avgGradientOfBlock?.contents(), 0, numBlocks * HistorgramSize * MemoryLayout<Float>.stride)
        }
        
        
        func procFrameData(rawImgPre: MTLTexture, rawImgCur: MTLTexture) throws ->MTLBuffer{
                
                resetBuffer()
                
                guard let commandBuffer = commandQueue.makeCommandBuffer(),
                      let sumBuffer = device.makeBuffer(length: HistorgramSize * MemoryLayout<Float>.stride, options: .storageModeShared) else{
                        throw ASError.gpuBufferErr
                }
                
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
                
                var w = self.videoWidth
                var h = self.videoHeight
                coder.setBuffer(self.projectionBuf, offset: 0, index: 4)
                coder.setBytes(&w, length: MemoryLayout<Int>.size, index: 5)
                coder.setBytes(&h, length: MemoryLayout<Int>.size, index: 6)
                var bSize = self.sideOfBlock
                coder.setBytes(&bSize, length: MemoryLayout<Int>.size, index: 7)
                
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
                var noBlock = self.numBlocks
                coder.setBytes(&noBlock, length: MemoryLayout<UInt>.size, index: 2)
                coder.dispatchThreadgroups(summerGroups,
                                           threadsPerThreadgroup: summerGroupSize)
                coder.endEncoding()
        }
        var counter:Int = 0
        func debugBuffer(sumGradient:MTLBuffer){
                let w = self.videoWidth
                let h = self.videoHeight
                saveRawDataToFile(fileName: "gpu_grayBufferA_\(counter).json", buffer: grayBufferCur!, width: w, height: h, type: UInt8.self)
                saveRawDataToFile(fileName: "gpu_grayBufferB_\(counter).json", buffer: grayBufferPre!, width: w, height: h, type: UInt8.self)
                saveRawDataToFile(fileName: "gpu_gradientXBuffer_\(counter).json", buffer: gradientBufferX!, width: w, height: h, type: Int16.self)
                saveRawDataToFile(fileName: "gpu_gradientYBuffer_\(counter).json", buffer: gradientBufferY!, width: w, height: h, type: Int16.self)
                saveRawDataToFile(fileName: "gpu_gradientTBuffer_\(counter).json", buffer: gradientBufferT!, width: w, height: h, type: UInt8.self)
                
                let numBlocksX = (self.videoWidth + self.sideOfBlock - 1) / self.sideOfBlock
                let numBlocksY = (self.videoHeight + self.sideOfBlock - 1) / self.sideOfBlock
                saveRawDataToFileWithDepth(fileName: "gpu_frame_quantity_\(self.sideOfBlock)_\(counter).json", buffer: avgGradientOfBlock!,
                                           width: numBlocksX, height: numBlocksY, depth: HistorgramSize, type: Float.self)
                saveRawDataToFile(fileName: "gpu_gradientSumOfOneFrame_\(counter).json", buffer: sumGradient,  width: 10, height: 1,  type: Float.self)
                counter+=1
        }
}
