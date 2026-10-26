import SpriteKit
import UIKit

/// Original PNGs stay unchanged. Slice in pixel coordinates, then crop every frame
/// in a clip to the SAME alpha union: no per-frame resizing or nearest filtering.
@MainActor
final class SpriteAssets {
    struct Clip {
        let textures: [SKTexture]
        let pixels: CGSize
        let visibleBounds: [CGRect]
    }
    private(set) var clips: [String: Clip] = [:]

    private let frameBounds: [String: [[CGFloat]]]
    init() {
        let url = Bundle.main.url(forResource: "sprite-bounds", withExtension: "json")!
        frameBounds = try! JSONDecoder().decode([String: [[CGFloat]]].self, from: Data(contentsOf: url))
        clips["leg-combo"] = Clip(textures: (1...9).map { index in
            let texture = SKTexture(imageNamed: String(format: "too-leg-combo-%02d", index))
            texture.filteringMode = .linear; return texture
        }, pixels: CGSize(width: 1536,height: 1152),visibleBounds: [])
        load("nado", file: "too-nado-spritesheet", width: 1024, height: 1024, count: 5)
        load("dev-presso", file: "dev-presso-spritesheet", width: 320, height: 330, count: 3)
        load("protein-toaster", file: "protein-toaster-spritesheet", width: 320, height: 330, count: 3)
        for key in ["dev-presso", "protein-toaster"] {
            let textures = (1...2).map { index in
                let texture = SKTexture(imageNamed: String(format: "%@-hit-%02d", key, index))
                texture.filteringMode = .linear
                return texture
            }
            clips["\(key)-hit"] = Clip(textures: textures, pixels: CGSize(width: 1024,height: 1024), visibleBounds: [])
        }
        load("espresso-cup", file: "dev-cup-01", width: 320, height: 330, count: 1)
        load("sandwich", file: "protein-sandwich-01", width: 320, height: 330, count: 1)
        load("armed-combo", file: "too-spatula-combo-chubby-v2", width: 1536, height: 1152, count: 6)
        load("armed-jump", file: "too-spatula-jump-spritesheet", width: 1254, height: 1254, count: 3)
        load("armed-idle", file: "too-spatula-idle-muted-v2", width: 1024, height: 1024, count: 4)
        load("armed-walk", file: "too-spatula-walk-muted-v2", width: 1024, height: 1024, count: 4)
        load("too-hit", file: "too-hit-spritesheet", width: 512, height: 512, count: 3)
        load("knockdown", file: "too-knockdown-spritesheet", width: 384, height: 384, count: 5)
        load("idle", file: "too-spritesheet", width: 384, height: 512, count: 6)
        load("walk", file: "too-walk-spritesheet", width: 384, height: 512, count: 6)
        load("jump", file: "too-jump-spritesheet", width: 512, height: 512, count: 6)
        load("punch", file: "too-punch-spritesheet", width: 512, height: 512, count: 3)
        load("goblin", file: "goblin-wobble-spritesheet", width: 384, height: 384, count: 3)
        load("hit", file: "goblin-hit-kick-spritesheet", width: 384, height: 384, count: 2)
    }

    private func load(_ key: String, file: String, width: Int, height: Int, count: Int) {
        guard let url = Bundle.main.url(forResource: file, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage else {
            preconditionFailure("Missing source asset: \(file)")
        }
        let columns = image.width / width
        precondition(columns > 0 && image.width % width == 0 && image.height % height == 0)
        precondition(count <= columns * image.height / height)
        let frames = (0..<count).map { i in
            image.cropping(to: CGRect(x: (i % columns) * width, y: (i / columns) * height,
                                     width: width, height: height))!
        }
        guard let measurements = frameBounds[key], measurements.count == count else {
            preconditionFailure("Regenerate sprite-bounds.json for \(key)")
        }
        let bounds = measurements.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        let measuredUnion = bounds.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -2, dy: -2)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        let union: CGRect
        if key == "armed-combo" {
            union = CGRect(x: 0, y: 0, width: 1536, height: 1091)
        } else if key == "armed-idle" || key == "armed-walk" {
            // Shared muted-v2 canvas crop preserves body scale and center on transitions.
            union = CGRect(x: 94, y: 56, width: 746, height: 849)
        } else {
            union = measuredUnion
        }
        let textures = frames.map { frame in
            let texture = SKTexture(cgImage: frame.cropping(to: union)!)
            texture.filteringMode = .linear
            return texture
        }
        clips[key] = Clip(textures: textures, pixels: union.size, visibleBounds: bounds)
    }

}
