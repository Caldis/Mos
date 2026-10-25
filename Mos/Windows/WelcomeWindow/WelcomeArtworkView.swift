import AppKit
import MetalKit

final class WelcomeArtworkView: NSView, MTKViewDelegate {
    private let metalView: MTKView?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var texture: MTLTexture?
    private var observers: [NSObjectProtocol] = []
    private var startedAt: CFTimeInterval = 0
    private var elapsed: CFTimeInterval = 0
    private var reduceMotion: Bool
    private var completed = false
    private var stopped = false
    private static let duration: CFTimeInterval = 4.2

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        let device = MTLCreateSystemDefaultDevice()
        metalView = device.map { MTKView(frame: .zero, device: $0) }
        queue = device?.makeCommandQueue()
        super.init(frame: .zero)
        setAccessibilityElement(false)
        guard let device, let metalView else {
            installFallback(); return
        }
        do {
            let library = try Self.makeShaderLibrary(device: device)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "logoVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "logoFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
            guard let image = NSApp.applicationIconImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                installFallback(); return
            }
            texture = try Self.makeLogoTexture(device: device, image: image)
        } catch {
            installFallback()
            return
        }
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.layer?.isOpaque = false
        metalView.preferredFramesPerSecond = 60
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = false
        metalView.delegate = self
        metalView.autoresizingMask = [.width, .height]
        metalView.frame = bounds
        addSubview(metalView)
    }

    static func makeShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        guard let sourceURL = Bundle.main.url(forResource: "LogoBirth", withExtension: "metal.txt") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try device.makeLibrary(source: String(contentsOf: sourceURL, encoding: .utf8), options: nil)
    }

    static func makeLogoTexture(device: MTLDevice, image: CGImage) throws -> MTLTexture {
        // Icon Services can return image formats that MTKTextureLoader cannot decode.
        let size = 512
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data else { throw CocoaError(.fileReadCorruptFile) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size,
                                                                 height: size, mipmapped: false)
        descriptor.storageMode = .managed
        if #available(macOS 10.15, *), device.hasUnifiedMemory { descriptor.storageMode = .shared }
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw CocoaError(.fileReadUnknown) }
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                        withBytes: pixels, bytesPerRow: size * 4)
        return texture
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { pause(); return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updatePlayback()
            })
        }
        updatePlayback()
    }

    override func layout() {
        super.layout()
        if completed || reduceMotion { metalView?.draw() }
    }

    func setReducedMotion(_ value: Bool) {
        guard reduceMotion != value else { return }
        reduceMotion = value
        updatePlayback()
    }

    func stop() {
        stopped = true
        pause()
        metalView?.delegate = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func updatePlayback() {
        guard !stopped, let window, window.isVisible, window.occlusionState.contains(.visible), !window.isMiniaturized else {
            pause(); return
        }
        if reduceMotion || completed {
            pause()
            metalView?.draw()
        } else if metalView?.isPaused == true {
            startedAt = CACurrentMediaTime()
            metalView?.isPaused = false
        }
    }

    private func pause() {
        if metalView?.isPaused == false { elapsed += CACurrentMediaTime() - startedAt }
        metalView?.isPaused = true
    }

    private func installFallback() {
        metalView?.removeFromSuperview()
        let image = NSImageView(image: NSApp.applicationIconImage)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 194), image.heightAnchor.constraint(equalToConstant: 194),
            image.centerXAnchor.constraint(equalTo: centerXAnchor), image.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !stopped, let pipeline, let texture, let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let command = queue?.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        var time = reduceMotion || completed ? Self.duration : elapsed
        // MTKView may request a drawable before its window becomes visible.
        if !reduceMotion, !completed, !view.isPaused, startedAt > 0 {
            time += CACurrentMediaTime() - startedAt
        }
        #if DEBUG
        if AppRuntime.isOnboardingPreview, !reduceMotion, !completed,
           ProcessInfo.processInfo.arguments.contains("--mos-preview-slow-animation") {
            time *= 0.1
        }
        #endif
        var uniforms = SIMD4<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height), Float(time), 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
        if time >= Self.duration, !completed {
            completed = true
            pause()
        }
    }
}
