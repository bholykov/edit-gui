//
//  EditBridge.swift
//  EditMac
//

import Cocoa
import MetalKit

enum EditInput {
    case keyboard(key: UInt16, modifiers: UInt)
    case mouse(x: Int, y: Int, button: Int)
    case newFile
    case save
}

class EditBridge: NSObject, MTKViewDelegate {

    private var metalView: MTKView
    private var commandQueue: MTLCommandQueue?
    private var editState: OpaquePointer?
    private var debugOnce = false
    private var pipelineState: MTLRenderPipelineState?
    private var textPipelineState: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var cellSize: CGSize = CGSize(width: 9, height: 18)
    private var font: NSFont
    private var glyphCache: [UInt32: MTLTexture] = [:]

    init(metalView: MTKView) {
        self.metalView = metalView
        self.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        super.init()

        guard let device = metalView.device else {
            fatalError("No Metal device available")
        }

        commandQueue = device.makeCommandQueue()

        // Create rendering pipeline
        setupPipeline(device: device)

        // Create sampler for text textures
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    func start() {
        let width = Int32(metalView.bounds.width)
        let height = Int32(metalView.bounds.height)

        print("    → Calling edit_init(\(width), \(height))...")
        editState = edit_init(width, height)

        if editState == nil {
            print("    ✗ FATAL: edit_init returned nil")
            fatalError("Failed to initialize Edit")
        }
        print("    ✓ Edit state initialized successfully")
    }

    func cleanup() {
        if let state = editState {
            edit_destroy(state)
            editState = nil
        }
    }

    private func setupPipeline(device: MTLDevice) {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float2 position [[attribute(0)]];
            float4 color [[attribute(1)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float4 color [[flat]];  // flat = no interpolation
        };

        vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
            VertexOut out;
            out.position = float4(in.position, 0.0, 1.0);
            out.color = in.color;
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertex_main")
            let fragmentFunction = library.makeFunction(name: "fragment_main")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

            // Set up vertex descriptor
            let vertexDescriptor = MTLVertexDescriptor()
            // Position attribute (2 floats)
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            // Color attribute (4 floats)
            vertexDescriptor.attributes[1].format = .float4
            vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
            vertexDescriptor.attributes[1].bufferIndex = 0
            // Layout
            vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 6
            vertexDescriptor.layouts[0].stepRate = 1
            vertexDescriptor.layouts[0].stepFunction = .perVertex

            pipelineDescriptor.vertexDescriptor = vertexDescriptor

            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

            // Create text rendering pipeline
            let textShaderSource = """
            #include <metal_stdlib>
            using namespace metal;

            struct TextVertexIn {
                float2 position [[attribute(0)]];
                float2 texCoord [[attribute(1)]];
                float4 color [[attribute(2)]];
            };

            struct TextVertexOut {
                float4 position [[position]];
                float2 texCoord;
                float4 color [[flat]];
            };

            vertex TextVertexOut text_vertex(TextVertexIn in [[stage_in]]) {
                TextVertexOut out;
                out.position = float4(in.position, 0.0, 1.0);
                out.texCoord = in.texCoord;
                out.color = in.color;
                return out;
            }

            fragment float4 text_fragment(TextVertexOut in [[stage_in]],
                                         texture2d<float> tex [[texture(0)]],
                                         sampler samp [[sampler(0)]]) {
                float alpha = tex.sample(samp, in.texCoord).r;
                return float4(in.color.rgb, in.color.a * alpha);
            }
            """

            let textLibrary = try device.makeLibrary(source: textShaderSource, options: nil)
            let textVertexFunction = textLibrary.makeFunction(name: "text_vertex")
            let textFragmentFunction = textLibrary.makeFunction(name: "text_fragment")

            let textPipelineDescriptor = MTLRenderPipelineDescriptor()
            textPipelineDescriptor.vertexFunction = textVertexFunction
            textPipelineDescriptor.fragmentFunction = textFragmentFunction
            textPipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
            textPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            textPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            textPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

            let textVertexDescriptor = MTLVertexDescriptor()
            textVertexDescriptor.attributes[0].format = .float2 // position
            textVertexDescriptor.attributes[0].offset = 0
            textVertexDescriptor.attributes[0].bufferIndex = 0
            textVertexDescriptor.attributes[1].format = .float2 // texCoord
            textVertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
            textVertexDescriptor.attributes[1].bufferIndex = 0
            textVertexDescriptor.attributes[2].format = .float4 // color
            textVertexDescriptor.attributes[2].offset = MemoryLayout<Float>.stride * 4
            textVertexDescriptor.attributes[2].bufferIndex = 0
            textVertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 8
            textVertexDescriptor.layouts[0].stepFunction = .perVertex

            textPipelineDescriptor.vertexDescriptor = textVertexDescriptor

            textPipelineState = try device.makeRenderPipelineState(descriptor: textPipelineDescriptor)

        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    private func createGlyphTexture(for character: UInt32, device: MTLDevice) -> MTLTexture? {
        guard let scalar = UnicodeScalar(character) else { return nil }
        let string = String(Character(scalar))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: string, attributes: attributes)
        let size = attrString.size()

        let width = Int(ceil(size.width)) + 2
        let height = Int(ceil(size.height)) + 2

        guard width > 0 && height > 0 else { return nil }

        // Create bitmap context
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // Clear and draw text
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(gray: 1, alpha: 1)
        context.textMatrix = .identity
        context.translateBy(x: 1, y: 1)

        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: 0, y: 0)
        CTLineDraw(line, context)

        // Create Metal texture
        guard let data = context.data else { return nil }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: width
        )

        return texture
    }

    func sendInput(_ input: EditInput) {
        guard let state = editState else { return }

        switch input {
        case .keyboard(let key, let modifiers):
            edit_handle_key(state, key, UInt32(modifiers))

        case .mouse(let x, let y, let button):
            edit_handle_mouse(state, Int32(x), Int32(y), Int32(button))

        case .newFile:
            edit_new_file(state)

        case .save:
            edit_save_file(state)
        }

        metalView.setNeedsDisplay(metalView.bounds)
    }

    func openFile(path: String) {
        guard let state = editState else { return }
        path.withCString { cPath in
            edit_open_file(state, cPath)
        }
        metalView.setNeedsDisplay(metalView.bounds)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let state = editState else { return }
        edit_resize(state, Int32(size.width), Int32(size.height))
    }

    func draw(in view: MTKView) {
        guard let state = editState,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        let renderData = edit_get_render_data(state)
        guard let data = renderData else {
            return
        }

        // Get cell count
        let cellCount = edit_render_data_cell_count(data)

        // Debug: Print first few cells (only once)
        if !debugOnce {
            var debugLog = "📊 Cell count: \(cellCount)\n"
            for i in 0..<min(30, cellCount) {
                if let cellPtr = edit_render_data_get_cell(data, i) {
                    let cell = cellPtr.pointee
                    if let scalar = UnicodeScalar(cell.ch) {
                        let char = Character(scalar)
                        let bg = cell.bg
                        let fg = cell.fg
                        debugLog += "  Cell[\(i)]: '\(char)' at (\(cell.x), \(cell.y)) bg=0x\(String(bg, radix: 16)) fg=0x\(String(fg, radix: 16))\n"
                    }
                }
            }
            try? debugLog.write(toFile: "/tmp/editmac-cells.log", atomically: true, encoding: .utf8)
            debugOnce = true
        }

        // Start render pass
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let pipeline = pipelineState,
              let device = metalView.device else {
            edit_free_render_data(data)
            return
        }

        renderEncoder.setRenderPipelineState(pipeline)

        // Render cell backgrounds
        var vertices: [Float] = []
        let viewWidth = Float(metalView.bounds.width)
        let viewHeight = Float(metalView.bounds.height)

        var debugColors = ""

        for i in 0..<min(1000, cellCount) { // Limit for now
            guard let cellPtr = edit_render_data_get_cell(data, i) else { continue }
            let cell = cellPtr.pointee

            // Calculate cell position in pixels
            let x = Float(cell.x) * Float(cellSize.width)
            let y = Float(cell.y) * Float(cellSize.height)
            let w = Float(cellSize.width)
            let h = Float(cellSize.height)

            // Convert to normalized device coordinates
            let x1 = (x / viewWidth) * 2.0 - 1.0
            let y1 = 1.0 - (y / viewHeight) * 2.0
            let x2 = ((x + w) / viewWidth) * 2.0 - 1.0
            let y2 = 1.0 - ((y + h) / viewHeight) * 2.0

            // Extract RGBA from background color (stored as ABGR u32 in native/little-endian)
            let bg = cell.bg
            let a = Float((bg >> 24) & 0xFF) / 255.0  // Alpha (high byte)
            let b = Float((bg >> 16) & 0xFF) / 255.0  // Blue
            let g = Float((bg >> 8) & 0xFF) / 255.0   // Green
            let r = Float(bg & 0xFF) / 255.0          // Red (low byte)

            if i < 30 {
                debugColors += "Cell[\(i)]: r=\(r) g=\(g) b=\(b) a=\(a)\n"
            }

            // Two triangles for rectangle (6 vertices)
            vertices.append(contentsOf: [
                x1, y1, r, g, b, a,  // top-left
                x2, y1, r, g, b, a,  // top-right
                x1, y2, r, g, b, a,  // bottom-left

                x2, y1, r, g, b, a,  // top-right
                x2, y2, r, g, b, a,  // bottom-right
                x1, y2, r, g, b, a,  // bottom-left
            ])
        }

        if !debugColors.isEmpty {
            try? debugColors.write(toFile: "/tmp/editmac-colors.log", atomically: true, encoding: .utf8)
        }

        if !vertices.isEmpty {
            let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: [])
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 6)
        }

        // Render text glyphs
        if let textPipeline = textPipelineState, let sampler = sampler {
            renderEncoder.setRenderPipelineState(textPipeline)
            renderEncoder.setFragmentSamplerState(sampler, index: 0)

            for i in 0..<min(100, cellCount) {
                guard let cellPtr = edit_render_data_get_cell(data, i) else { continue }
                let cell = cellPtr.pointee

                // Skip spaces
                if cell.ch == 32 { continue }

                // Get or create glyph texture
                let texture: MTLTexture
                if let cached = glyphCache[cell.ch] {
                    texture = cached
                } else {
                    guard let newTexture = createGlyphTexture(for: cell.ch, device: device) else { continue }
                    glyphCache[cell.ch] = newTexture
                    texture = newTexture
                }

                // Calculate position
                let x = Float(cell.x) * Float(cellSize.width)
                let y = Float(cell.y) * Float(cellSize.height)
                let w = Float(texture.width)
                let h = Float(texture.height)

                // Convert to NDC
                let x1 = (x / viewWidth) * 2.0 - 1.0
                let y1 = 1.0 - (y / viewHeight) * 2.0
                let x2 = ((x + w) / viewWidth) * 2.0 - 1.0
                let y2 = 1.0 - ((y + h) / viewHeight) * 2.0

                // Extract foreground color
                let fg = cell.fg
                let a = Float((fg >> 24) & 0xFF) / 255.0
                let b = Float((fg >> 16) & 0xFF) / 255.0
                let g = Float((fg >> 8) & 0xFF) / 255.0
                let r = Float(fg & 0xFF) / 255.0

                // Create vertex data with texture coordinates
                let textVertices: [Float] = [
                    x1, y1, 0, 0, r, g, b, a,  // top-left
                    x2, y1, 1, 0, r, g, b, a,  // top-right
                    x1, y2, 0, 1, r, g, b, a,  // bottom-left

                    x2, y1, 1, 0, r, g, b, a,  // top-right
                    x2, y2, 1, 1, r, g, b, a,  // bottom-right
                    x1, y2, 0, 1, r, g, b, a,  // bottom-left
                ]

                let buffer = device.makeBuffer(bytes: textVertices, length: textVertices.count * MemoryLayout<Float>.stride, options: [])
                renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
                renderEncoder.setFragmentTexture(texture, index: 0)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        edit_free_render_data(data)
    }
}

@_silgen_name("edit_init")
func edit_init(_ width: Int32, _ height: Int32) -> OpaquePointer?

@_silgen_name("edit_destroy")
func edit_destroy(_ state: OpaquePointer)

@_silgen_name("edit_handle_key")
func edit_handle_key(_ state: OpaquePointer, _ key: UInt16, _ modifiers: UInt32)

@_silgen_name("edit_handle_mouse")
func edit_handle_mouse(_ state: OpaquePointer, _ x: Int32, _ y: Int32, _ button: Int32)

@_silgen_name("edit_new_file")
func edit_new_file(_ state: OpaquePointer)

@_silgen_name("edit_open_file")
func edit_open_file(_ state: OpaquePointer, _ path: UnsafePointer<CChar>)

@_silgen_name("edit_save_file")
func edit_save_file(_ state: OpaquePointer)

@_silgen_name("edit_resize")
func edit_resize(_ state: OpaquePointer, _ width: Int32, _ height: Int32)

@_silgen_name("edit_get_render_data")
func edit_get_render_data(_ state: OpaquePointer) -> OpaquePointer?

@_silgen_name("edit_free_render_data")
func edit_free_render_data(_ data: OpaquePointer?)

@_silgen_name("edit_render_data_cell_count")
func edit_render_data_cell_count(_ data: OpaquePointer?) -> Int32

@_silgen_name("edit_render_data_get_cell")
func edit_render_data_get_cell(_ data: OpaquePointer?, _ index: Int32) -> UnsafePointer<FramebufferCell>?

struct FramebufferCell {
    let ch: UInt32          // Rust char (4 bytes, UTF-32)
    let fg: UInt32          // StraightRgba (4 bytes)
    let bg: UInt32          // StraightRgba (4 bytes)
    let attrs: UInt8        // Attributes (1 byte)
    let _padding1: UInt8    // padding
    let _padding2: UInt8    // padding
    let _padding3: UInt8    // padding
    let x: Int              // CoordType/isize (8 bytes)
    let y: Int              // CoordType/isize (8 bytes)
}
