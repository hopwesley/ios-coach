import SwiftUI
import MetalKit

func fillTextureWithPattern(texture: MTLTexture) {
    let width = texture.width
    let height = texture.height
    let bytesPerPixel = 1  // 单通道
    let bytesPerRow = width * bytesPerPixel
    var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let index = y * width + x
            data[index] = UInt8(index % 256)
        }
    }

    data.withUnsafeBytes { buffer in
        texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: buffer.baseAddress!,
                        bytesPerRow: bytesPerRow)
    }
}

struct MetalKitViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.framebufferOnly = false
        mtkView.delegate = context.coordinator
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.drawableSize = CGSize(width: 256, height: 256)  // 确保与视图尺寸一致
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // 更新 UI 视图时需要执行的操作（这里可能不需要实现任何内容）
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalKitViewContainer
        var texture: MTLTexture?
        var commandQueue: MTLCommandQueue?
        var pipelineState: MTLRenderPipelineState?
        var samplerState: MTLSamplerState?

        init(_ parent: MetalKitViewContainer) {
            self.parent = parent
            super.init()
            if let device = MTLCreateSystemDefaultDevice() {
                self.commandQueue = device.makeCommandQueue()
                self.texture = setupTexture(device: device)
                fillTextureWithPattern(texture: self.texture!)
                setupPipelineState(device: device)
                setupSamplerState(device: device)
            }
        }

        func setupTexture(device: MTLDevice) -> MTLTexture? {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,  // 单通道，8位灰度纹理
                width: 256,
                height: 256,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead, .shaderWrite]
            return device.makeTexture(descriptor: textureDescriptor)
        }

        func setupPipelineState(device: MTLDevice) {
            guard let defaultLibrary = device.makeDefaultLibrary(),
                  let vertexFunction = defaultLibrary.makeFunction(name: "basic_vertex"),
                  let fragmentFunction = defaultLibrary.makeFunction(name: "basic_fragment") else {
                fatalError("Unable to load vertex or fragment function.")
            }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                fatalError("Unable to create pipeline state object, error: \(error)")
            }
        }

        func setupSamplerState(device: MTLDevice) {
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .nearest
            samplerDescriptor.magFilter = .nearest
            samplerDescriptor.mipFilter = .notMipmapped
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pipelineState = pipelineState,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let passDescriptor = view.currentRenderPassDescriptor,
                  let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
                return
            }

            commandEncoder.setRenderPipelineState(pipelineState)
            commandEncoder.setFragmentTexture(texture, index: 0)
            commandEncoder.setFragmentSamplerState(samplerState, index: 0)

            let vertexData: [Float] = [
                -1.0,  1.0, 0.0, 1.0,
                 1.0,  1.0, 0.0, 1.0,
                -1.0, -1.0, 0.0, 1.0,
                 1.0, -1.0, 0.0, 1.0
            ]
            let vertexBuffer = view.device?.makeBuffer(bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: [])
            commandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            commandEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // 当视图大小变化时，这里可以进行相应的处理
        }
    }
}

struct ContentView: View {
    var body: some View {
        MetalKitViewContainer()
            .frame(width: 300, height: 300)
            .edgesIgnoringSafeArea(.all)
    }
}
