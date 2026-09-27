import AppKit
import MetalKit
import SwiftUI
import simd

/// Art direction only. The preserved v008 samples and graph IDs remain exact.
/// Frame-based framing follows the displayed sample, including slow disk reads.
enum LiminalSeedStyle {
    static let revision = "garnet-seed/v1"
    static func weight(frame: Int) -> Float {
        let t = min(1, max(0, Float(frame - 90) / 18))
        return t * t * (3 - 2 * t)
    }
    static func framing(center: SIMD3<Float>, span: Float, frame: Int) -> (center: SIMD3<Float>, span: Float) {
        let amount = weight(frame: frame)
        return (center + (SIMD3<Float>(0, 1.15, center.z) - center) * amount,
                span + (1.90 - span) * amount)
    }
    static func color(_ color: CompanionSeedColor) -> CompanionSeedColor { color == .original ? .garnet : color }
}

/// A transparent view of authenticated baked samples. It owns no companion,
/// graph, progression or simulation state. Progress is supplied by the owner.
@MainActor
struct LiminalMetalView: NSViewRepresentable {
    let asset: LiminalPointAsset
    let progress: Double
    let reduceMotion: Bool
    let isVisible: Bool
    var seedColor: CompanionSeedColor = .original
    var lightIntensity: Float = 1
    var selectableIDs: [UInt32] = []
    var onSelectArtID: ((UInt32) -> Void)? = nil

    func makeNSView(context: Context) -> LiminalMetalSurface {
        let surface = LiminalMetalSurface(frame: .zero)
        surface.configure(self)
        return surface
    }
    func updateNSView(_ surface: LiminalMetalSurface, context: Context) { surface.configure(self) }
    static func dismantleNSView(_ surface: LiminalMetalSurface, coordinator: ()) { surface.stop() }

    /// An explicit, bounded offscreen snapshot using the exact live GPU pipeline.
    /// Call only for a qualified asset. Failure does not substitute another asset.
    static func snapshotPNGData(asset: LiminalPointAsset, progress: Double,
                                seedColor: CompanionSeedColor = .original,
                                lightIntensity: Float = 1) throws -> Data {
        guard let device = MTLCreateSystemDefaultDevice() else { throw LiminalMetalFailure.unavailable }
        let renderer = try LiminalMetalPipeline(device: device)
        let seedTexture = renderer.seedTexture(color: seedColor)
        let pair = try asset.framePair(progress: progress, detail: .medium)
        let buffers = try renderer.buffers(pair)
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 512, height: 512, mipmapped: false)
        description.usage = [.renderTarget]
        description.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: description), let command = renderer.queue.makeCommandBuffer() else {
            throw LiminalMetalFailure.unavailable
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        try renderer.encode(command: command, pass: pass, buffers: buffers, count: pair.lower.pointCount,
            uniforms: .init(asset: asset, size: CGSize(width: 512, height: 512), fraction: pair.fraction,
                            seedColor: seedColor, lightIntensity: lightIntensity, frame: pair.lower.frame,
                            seedAvailable: seedTexture != nil), seedTexture: seedTexture)
        let completed = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in completed.signal() }
        command.commit()
        guard completed.wait(timeout: .now() + 3) == .success, command.status == .completed else {
            throw LiminalMetalFailure.snapshotFailed
        }
        var bytes = [UInt8](repeating: 0, count: 512 * 512 * 4)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: 512 * 4, from: MTLRegionMake2D(0, 0, 512, 512), mipmapLevel: 0)
        }
        // Metal readback is BGRA. ImageIO/AppKit receives ordinary RGBA bytes.
        for index in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(index, index + 2) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: 512, height: 512, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 512 * 4,
                space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw LiminalMetalFailure.snapshotFailed
        }
        return png
    }
}

private enum LiminalMetalFailure: Error { case unavailable, snapshotFailed }

/// No geometry shader is used: each authored point becomes six instanced quad
/// vertices. This path works on native Metal and has a direct Unity quad analogue.
private struct LiminalMetalPipeline {
    struct Buffers { let lower: MTLBuffer; let upper: MTLBuffer; let anchors: MTLBuffer }
    struct Uniforms {
        var centerAndScale: SIMD4<Float>
        var viewportAndFraction: SIMD4<Float>
        var tintAndAmount: SIMD4<Float>
        var intensityAndPadding: SIMD4<Float>
        init(asset: LiminalPointAsset, size: CGSize, fraction: Float,
             seedColor: CompanionSeedColor, lightIntensity: Float, frame: Int,
             seedAvailable: Bool, inspection: Bool = false) {
            let framing = LiminalSeedStyle.framing(center: asset.center, span: asset.span, frame: frame)
            centerAndScale = SIMD4(framing.center, 2 / framing.span)
            viewportAndFraction = SIMD4(Float(max(1, size.width)), Float(max(1, size.height)), fraction, 0)
            let palette: Float
            switch seedColor {
            case .original: palette = 0
            case .aqua: palette = 1
            case .garnet: palette = 2
            case .violet: palette = 3
            case .gold: palette = 4
            case .pearl: palette = 5
            }
            // Matches the Unity palette function, preserving neutral/gold points.
            tintAndAmount = SIMD4(palette, 0, 0, 0)
            let seed = seedAvailable && !inspection ? LiminalSeedStyle.weight(frame: frame) : 0
            intensityAndPadding = SIMD4(lightIntensity.isFinite ? min(2, max(0, lightIntensity)) : 1,
                                        inspection ? 1 : 0, 1 - 0.85 * seed, seed)
        }
    }
    let device: MTLDevice
    let queue: MTLCommandQueue
    let state: MTLRenderPipelineState
    let seedState: MTLRenderPipelineState
    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else { throw LiminalMetalFailure.unavailable }
        self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "liminal_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "liminal_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        state = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.vertexFunction = library.makeFunction(name: "liminal_seed_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "liminal_seed_fragment")
        seedState = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    @MainActor func seedTexture(color: CompanionSeedColor) -> MTLTexture? {
        guard let image = SeedColorRendering.image(for: .hamptonSeed, color: LiminalSeedStyle.color(color)),
              let bitmap = SeedColorRendering.rgba(image) else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: bitmap.width, height: bitmap.height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bitmap.bytes.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: bitmap.width * 4)
        }
        return texture
    }
    func buffers(_ pair: LiminalPointAsset.FramePair, anchorIndices: [Int] = []) throws -> Buffers {
        func make(_ data: Data) throws -> MTLBuffer {
            guard let buffer = data.withUnsafeBytes({ bytes in
                bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
            }) else { throw LiminalMetalFailure.unavailable }
            return buffer
        }
        let first = try make(pair.lower.data)
        let second = pair.lower.data == pair.upper.data ? first : try make(pair.upper.data)
        var anchors = [UInt32](repeating: 0, count: pair.lower.pointCount)
        for index in anchorIndices where anchors.indices.contains(index) { anchors[index] = 1 }
        guard let anchorBuffer = anchors.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
            throw LiminalMetalFailure.unavailable
        }
        return .init(lower: first, upper: second, anchors: anchorBuffer)
    }
    func encode(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, buffers: Buffers,
                count: Int, uniforms: Uniforms, seedTexture: MTLTexture?) throws {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw LiminalMetalFailure.unavailable }
        encoder.setRenderPipelineState(state)
        encoder.setVertexBuffer(buffers.lower, offset: 0, index: 0)
        encoder.setVertexBuffer(buffers.upper, offset: 0, index: 1)
        encoder.setVertexBuffer(buffers.anchors, offset: 0, index: 3)
        var copy = uniforms
        encoder.setVertexBytes(&copy, length: MemoryLayout<Uniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        if uniforms.intensityAndPadding.w > 0, let seedTexture {
            encoder.setRenderPipelineState(seedState)
            encoder.setFragmentTexture(seedTexture, index: 0)
            encoder.setFragmentBytes(&copy, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        encoder.endEncoding()
    }
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Point { packed_float3 p; packed_float3 cd; float radius; float emission; };
    struct Uniforms { float4 centerScale; float4 viewportFraction; float4 tintAmount; float4 intensity; };
    struct Raster { float4 position [[position]]; float2 local; float3 color; float opacity; };
    float3 palette(float3 c, float choice) {
        if (choice < 0.5f) return c;
        float hi=max(c.r,max(c.g,c.b)),lo=min(c.r,min(c.g,c.b));
        if(hi<0.0001f || (hi-lo)/hi<0.12f || (c.r>c.b*1.2f && c.g>c.b*1.2f && c.g>c.r*0.18f)) return c;
        float3 tint=choice<1.5f?float3(0.05f,1,0.72f):choice<2.5f?float3(1,0.03f,0.20f):
            choice<3.5f?float3(0.52f,0.10f,1):choice<4.5f?float3(1,0.65f,0.06f):float3(1);
        return mix(float3(hi),tint*hi,saturate((hi-lo)/hi));
    }
    vertex Raster liminal_vertex(uint vertexID [[vertex_id]], uint pointID [[instance_id]],
        const device Point *a [[buffer(0)]], const device Point *b [[buffer(1)]], constant Uniforms &u [[buffer(2)]],
        const device uint *selected [[buffer(3)]]) {
        const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
        float t = u.viewportFraction.z;
        float3 p = mix(float3(a[pointID].p),float3(b[pointID].p),t);
        float3 cd = max(float3(0),mix(float3(a[pointID].cd),float3(b[pointID].cd),t));
        float anchor = u.intensity.y > 0.5f && selected[pointID] != 0 ? 1.0f : 0.0f;
        float radius = max(0.00001f,mix(a[pointID].radius,b[pointID].radius,t));
        float emission = clamp(mix(a[pointID].emission,b[pointID].emission,t),0.0f,8.0f);
        float2 viewport = max(float2(1),u.viewportFraction.xy);
        float side = min(viewport.x,viewport.y);
        float2 aspect = side/viewport;
        float2 center = (p.xy-u.centerScale.xy)*u.centerScale.w*aspect;
        float radiusPixels = max(0.5f,radius*u.centerScale.w*side*0.5f);
        radiusPixels = mix(radiusPixels,max(radiusPixels*2.5f,3.0f),anchor);
        cd = palette(cd,u.tintAmount.x);
        cd = mix(cd,float3(0.9f,0.65f,0.16f),anchor*0.55f);
        float3 radiance = min(cd*emission*u.intensity.x,float3(8));
        Raster out;
        out.position = float4(center+corners[vertexID]*(2.0f*radiusPixels/viewport),0.5f,1);
        out.local = corners[vertexID]; out.color = radiance; out.opacity = u.intensity.z;
        return out;
    }
    fragment float4 liminal_fragment(Raster in [[stage_in]]) {
        float squared = dot(in.local,in.local);
        if (squared >= 1.0f) discard_fragment();
        float alpha = saturate(exp(-squared*4.0f)*(1.0f-squared)*in.opacity);
        float3 linear = 1.0f-exp(-in.color);
        float3 srgb = select(12.92f*linear, 1.055f*pow(linear,float3(1.0f/2.4f))-0.055f,
                             linear > 0.0031308f);
        // AppKit consumes premultiplied display-space RGBA. Encode BEFORE
        // premultiplication; the unorm target avoids a second RGB conversion.
        return float4(srgb*alpha,alpha);
    }
    struct SeedRaster { float4 position [[position]]; float2 uv; };
    vertex SeedRaster liminal_seed_vertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(2)]]) {
        const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
        float2 viewport = max(float2(1),u.viewportFraction.xy);
        SeedRaster out;
        float2 aspect = min(viewport.x,viewport.y)/viewport;
        float2 center = (float2(0,1.15f)-u.centerScale.xy)*u.centerScale.w;
        out.position = float4((center+corners[id]*0.95f*u.centerScale.w)*aspect,0.4f,1);
        out.uv = float2(corners[id].x*0.5f+0.5f,0.5f-corners[id].y*0.5f);
        return out;
    }
    fragment float4 liminal_seed_fragment(SeedRaster in [[stage_in]], texture2d<float> art [[texture(0)]],
                                        constant Uniforms &u [[buffer(2)]]) {
        constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 color = art.sample(linearSampler,in.uv); // Already premultiplied sRGB.
        color.rgb = min(color.rgb*u.intensity.x,float3(color.a));
        return color*u.intensity.w;
    }
    """
}

@MainActor
final class LiminalMetalSurface: MTKView, @preconcurrency MTKViewDelegate {
    private var configuration: LiminalMetalView?
    private var pipeline: LiminalMetalPipeline?
    private var seedTexture: MTLTexture?
    private var seedTextureColor: CompanionSeedColor?
    private var buffers: LiminalMetalPipeline.Buffers?
    private struct Anchor { let id: UInt32; let lower: LiminalPointAsset.Sample; let upper: LiminalPointAsset.Sample }
    private var anchors: [Anchor] = []
    private var frameNumbers: (lower: Int, upper: Int)?
    private var pointCount = 0
    private var displayedFraction: Float = 0
    private var loadedKey: String?
    private var loadingKey: String?
    private var failedKey: String?
    private var loading: Task<Void, Never>?
    private var detail = LiminalPointAsset.Detail.medium
    private var slowFrames = 0
    private var fastGPUFrames = 0
    private var lastFrameAt: Double?
    private var observers: [NSObjectProtocol] = []
    private let fallbackImage = NSImageView()
    private var fallbackKey: String?
    private var fallbackLoading: Task<Void, Never>?
    private var usesFallback: Bool { pipeline == nil || failedKey != nil }

    override init(frame frameRect: NSRect, device: MTLDevice? = nil) {
        let actualDevice = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: actualDevice)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        preferredFramesPerSecond = 30
        enableSetNeedsDisplay = false
        isPaused = true
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        fallbackImage.frame = bounds
        fallbackImage.autoresizingMask = [.width, .height]
        fallbackImage.imageScaling = .scaleProportionallyUpOrDown
        fallbackImage.isHidden = true
        addSubview(fallbackImage)
        delegate = self
        if let actualDevice { pipeline = try? LiminalMetalPipeline(device: actualDevice) }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateVisibility() }
            })
        }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateVisibility() }
    override func viewDidHide() { super.viewDidHide(); updateVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateVisibility() }

    func configure(_ next: LiminalMetalView) {
        if configuration?.asset.manifestSHA256 != next.asset.manifestSHA256 {
            loading?.cancel(); loading = nil; loadingKey = nil; loadedKey = nil
            failedKey = nil
            fallbackLoading?.cancel(); fallbackLoading = nil; fallbackKey = nil
            fallbackImage.image = nil; fallbackImage.isHidden = true
            frameNumbers = nil; anchors = []; buffers = nil; detail = .medium; slowFrames = 0
        }
        if configuration?.selectableIDs != next.selectableIDs { loadedKey = nil; anchors = [] }
        if seedTextureColor != next.seedColor {
            seedTexture = pipeline?.seedTexture(color: next.seedColor)
            seedTextureColor = next.seedColor
        }
        configuration = next
        updateVisibility()
        if isPaused, next.isVisible { setNeedsDisplay(bounds) }
    }
    func stop() {
        isPaused = true; loading?.cancel(); loading = nil; frameNumbers = nil; anchors = []; buffers = nil
        fallbackLoading?.cancel(); fallbackLoading = nil; fallbackKey = nil; fallbackImage.image = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []; delegate = nil; configuration = nil; seedTexture = nil
    }
    private var canPresentPoints: Bool {
        configuration?.isVisible == true && NSApp.isActive && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }
    private func updateVisibility() {
        isPaused = !canPresentPoints || configuration?.reduceMotion == true || usesFallback
        fallbackImage.isHidden = !canPresentPoints || !usesFallback || fallbackImage.image == nil
        if !canPresentPoints {
            lastFrameAt = nil; loading?.cancel(); loading = nil; loadingKey = nil
            if fallbackLoading != nil { fallbackLoading?.cancel(); fallbackLoading = nil; fallbackKey = nil }
        }
        if canPresentPoints && usesFallback { requestFallback(); return }
        if canPresentPoints && isPaused { draw() }
    }
    private func requestFallback() {
        guard canPresentPoints, usesFallback, let c = configuration else { return }
        let progress = effectiveProgress
        let endpoint = [23.0 / 119, 65.0 / 119, 107.0 / 119].min { abs($0 - progress) < abs($1 - progress) }!
        let key = "\(c.asset.manifestSHA256):\(endpoint):\(c.seedColor.rawValue)"
        guard fallbackKey != key else { return }
        fallbackLoading?.cancel(); fallbackKey = key
        fallbackImage.image = nil; fallbackImage.isHidden = true
        if endpoint == 107.0 / 119, let seed = SeedColorRendering.image(for: .hamptonSeed, color: LiminalSeedStyle.color(c.seedColor)) {
            fallbackImage.image = seed
            fallbackImage.setAccessibilityLabel("Authored Liminal Seed artwork; particle rendering unavailable.")
            fallbackImage.isHidden = false
            return
        }
        let status = "Reference endpoint fallback; not an exact GPU capture."
        fallbackImage.setAccessibilityLabel(status)
        fallbackImage.toolTip = status
        setAccessibilityLabel("Liminal: \(status)")
        let asset = c.asset, color = c.seedColor
        fallbackLoading = Task { [weak self] in
            let task = Task.detached(priority: .utility) { try asset.endpointPNGData(progress: endpoint) }
            do {
                let data = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled, let self, self.fallbackKey == key, self.canPresentPoints, self.usesFallback else { return }
                self.fallbackLoading = nil
                guard let data, let original = NSImage(data: data),
                      let image = SeedColorRendering.recolor(original, color: color, preserveGold: true) else {
                    self.setAccessibilityLabel("Liminal reference endpoint fallback unavailable.")
                    return
                }
                self.fallbackImage.image = image
                self.fallbackImage.isHidden = false
            } catch {
                guard !Task.isCancelled, let self, self.fallbackKey == key else { return }
                self.fallbackLoading = nil
                self.setAccessibilityLabel("Liminal reference endpoint fallback unavailable: verification failed.")
            }
        }
    }
    private var effectiveProgress: Double {
        guard let c = configuration, c.progress.isFinite else { return 0 }
        let value = min(1, max(0, c.progress))
        guard c.reduceMotion else { return value }
        // Reduced motion selects an authored endpoint, never a synthetic morph.
        return [23.0 / 119, 65.0 / 119, 107.0 / 119].min { abs($0 - value) < abs($1 - value) }!
    }
    private func requestFrames(_ c: LiminalMetalView, progress: Double) -> String {
        let index = (try? LiminalPointAsset.sourceFrameIndex(progress: progress)) ?? 0
        let key = "\(c.asset.manifestSHA256):\(c.asset.manifest.frames[index].file):\(detail.rawValue)"
        guard key != loadedKey, key != loadingKey, failedKey == nil, loading == nil else { return key }
        loadingKey = key
        // Only GPU buffers and bounded anchor samples survive a load. At most
        // two full CPU frame prefixes exist, with no whole-clip cache.
        let asset = c.asset, requestedDetail = detail
        loading = Task { [weak self] in
            let task = Task.detached(priority: .userInitiated) { try asset.framePair(progress: progress, detail: requestedDetail) }
            do {
                let frames = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled, let self, self.loadingKey == key, self.canPresentPoints,
                      self.configuration?.asset.manifestSHA256 == asset.manifestSHA256,
                      let pipeline = self.pipeline else { return }
                let indices = (self.configuration?.selectableIDs ?? []).prefix(512).compactMap { id in
                    asset.artIDs.firstIndex(of: id).flatMap { $0 < frames.lower.pointCount ? $0 : nil }
                }
                let uploaded = try pipeline.buffers(frames, anchorIndices: indices)
                self.anchors = indices.compactMap { index in
                    guard let a = frames.lower.sample(at: index), let b = frames.upper.sample(at: index) else { return nil }
                    return Anchor(id: asset.artIDs[index], lower: a, upper: b)
                }
                self.frameNumbers = (frames.lower.frame, frames.upper.frame)
                self.pointCount = frames.lower.pointCount
                self.buffers = uploaded; self.loadedKey = key
                self.loading = nil; self.loadingKey = nil
                if self.isPaused { self.draw() }
            } catch {
                guard let self, self.loadingKey == key else { return }
                self.loading = nil; self.loadingKey = nil; self.loadedKey = nil
                self.frameNumbers = nil; self.anchors = []; self.buffers = nil; self.failedKey = key
                self.clearSurface()
                self.updateVisibility()
            }
        }
        return key
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { if isPaused && canPresentPoints { draw() } }
    func draw(in view: MTKView) {
        guard canPresentPoints, let c = configuration else { return }
        guard !usesFallback, let pipeline else { requestFallback(); return }
        let progress = effectiveProgress
        let key = requestFrames(c, progress: progress)
        guard frameNumbers != nil, let buffers,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = pipeline.queue.makeCommandBuffer() else { return }
        // A slow read may complete behind the owner's timeline. Display that
        // authenticated source sample while the next one loads. Both buffers
        // contain the same rounded v008 frame; never invent fractional motion.
        let fraction: Float = 0
        displayedFraction = fraction
        do {
            try pipeline.encode(command: command, pass: pass, buffers: buffers, count: pointCount,
                uniforms: .init(asset: c.asset, size: drawableSize, fraction: fraction,
                                seedColor: c.seedColor, lightIntensity: c.lightIntensity,
                                frame: frameNumbers!.lower, seedAvailable: seedTexture != nil,
                                inspection: !c.selectableIDs.isEmpty), seedTexture: seedTexture)
        } catch {
            failedKey = key; anchors = []; self.buffers = nil
            clearSurface(); updateVisibility(); return
        }
        command.present(drawable)
        command.addCompletedHandler { [weak self] buffer in
            let duration = buffer.gpuEndTime - buffer.gpuStartTime
            Task { @MainActor [weak self] in self?.observeGPUTime(duration) }
        }
        command.commit()
        let now = ProcessInfo.processInfo.systemUptime
        if let lastFrameAt, !c.reduceMotion {
            slowFrames = now - lastFrameAt > 1.0 / 27 ? slowFrames + 1 : max(0, slowFrames - 1)
            if slowFrames >= 8, detail != .low {
                detail = detail == .high ? .medium : .low
                loadedKey = nil; slowFrames = 0
            }
        }
        lastFrameAt = now
    }

    private func observeGPUTime(_ duration: Double) {
        guard duration.isFinite, duration > 0, canPresentPoints, configuration?.reduceMotion == false else { return }
        fastGPUFrames = duration < 0.012 ? fastGPUFrames + 1 : 0
        if duration > 1.0 / 30, detail != .low {
            detail = detail == .high ? .medium : .low
            loadedKey = nil; fastGPUFrames = 0
        } else if fastGPUFrames >= 90, detail != .high {
            detail = detail == .low ? .medium : .high
            loadedKey = nil; fastGPUFrames = 0
        }
    }
    private func clearSurface() {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let command = pipeline?.queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding(); command.present(drawable); command.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !usesFallback, let c = configuration, c.onSelectArtID != nil, !anchors.isEmpty, !c.selectableIDs.isEmpty else { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        guard canPresentPoints, !usesFallback, let c = configuration, let callback = c.onSelectArtID, !c.selectableIDs.isEmpty else { return }
        let location = convert(event.locationInWindow, from: nil)
        let framing = LiminalSeedStyle.framing(center: c.asset.center, span: c.asset.span, frame: frameNumbers?.lower ?? 1)
        let side = min(bounds.width, bounds.height), span = CGFloat(framing.span)
        var closest: (id: UInt32, distance: CGFloat)?
        // Only the owner's explicit anchors are selectable; arbitrary art points
        // cannot masquerade as graph records. Bound selection work separately.
        for anchor in anchors where c.selectableIDs.contains(anchor.id) {
            let position = anchor.lower.position + (anchor.upper.position - anchor.lower.position) * displayedFraction
            let radius = anchor.lower.radius + (anchor.upper.radius - anchor.lower.radius) * displayedFraction
            let x = bounds.midX + CGFloat(position.x - framing.center.x) * side / span
            let y = bounds.midY + CGFloat(position.y - framing.center.y) * side / span
            let distance = hypot(location.x - x, location.y - y)
            let hitRadius = max(8, CGFloat(radius) * 2.5 * side / span)
            if distance <= hitRadius, closest == nil || distance < closest!.distance { closest = (anchor.id, distance) }
        }
        if let closest { callback(closest.id) }
    }
}
