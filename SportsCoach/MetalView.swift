import SwiftUI
import MetalKit

// SwiftUI view that integrates a MTKView for Metal rendering
struct MetalView: View {
    var body: some View {
        MetalKitView()
            .frame(width: 300, height: 300)
            .onAppear {
                MTKViewCoordinator.shared.setup()
            }
    }
}

// UIViewRepresentable wrapper for MTKView to be used in SwiftUI
struct MetalKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        return MTKViewCoordinator.shared.mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        // Handle view updates if needed
    }
}

// Coordinator for handling Metal setup and rendering, inheriting from NSObject
class MTKViewCoordinator: NSObject, MTKViewDelegate {
    static let shared = MTKViewCoordinator()
    let mtkView: MTKView
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        mtkView = MTKView()
        mtkView.device = device
        commandQueue = device.makeCommandQueue()!
        
        // Basic clear screen setup
        mtkView.clearColor = MTLClearColorMake(0, 0, 1, 1) // Blue background
        mtkView.enableSetNeedsDisplay = true
        
        super.init()
        mtkView.delegate = self
    }
    
    func setup() {
        // Additional setup if needed
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        
        if let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            // Here you can add commands to the encoder for drawing
            commandEncoder.endEncoding()
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Implement any adjustments when the drawable size of the view changes.
        // This method is required but can be left empty if no size change handling is needed.
    }
}
