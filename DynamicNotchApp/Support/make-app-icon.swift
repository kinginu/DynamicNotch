#!/usr/bin/env swift
// Generates the DynamicNotch app icon (reproducible; no image editor involved).
//
//   cd DynamicNotchApp && swift Support/make-app-icon.swift
//
// Outputs
//   Support/DynamicNotchAppIcon.icns  (16…1024 px incl. @2x; project.yml → CFBundleIconFile). Not named
//                                    "AppIcon", so it never collides with an asset-catalog "AppIcon" image
//                                    (NSBundle image lookup prefers the catalog over a loose .icns).
//   docs/app-icon/preview.png     (2× preview: large icon on light/dark, small sizes, menu bar glyph)
//
// Design (macOS 26 system-icon style): the standard macOS icon grid — 1024 px canvas, 824 px
// continuous-corner squircle inset 100 px with the grid's soft drop shadow — filled
// with a calm graphite two-tone gradient and a faint top light; one white glyph, centred: a stylised
// notch (flat top with small concave "shoulders" where it meets the bezel, rounded bottom corners)
// hanging from the top edge of a display outline, with a small three-blade fan in the screen.
// No text, no 3D props, no SF Symbols (Apple's SF Symbols licence excludes app icons).
import AppKit
import CoreGraphics
import SwiftUI

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let supportDir = root.appendingPathComponent("Support")
let previewURL = root.appendingPathComponent("docs/app-icon/preview.png")

// MARK: - Palette

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let bgTop = rgb(0x4A4E57)      // graphite, lit
let bgBottom = rgb(0x1B1C20)   // graphite, deep
let glyph = rgb(0xFFFFFF)

// MARK: - Geometry (in 1024-unit icon space, y up)

/// The notch: flat top edge (with concave shoulders that flare into the "bezel"), straight sides,
/// generously rounded bottom corners.
func notchPath(center: CGPoint, width w: CGFloat, height h: CGFloat, shoulder s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let left = center.x - w / 2, right = center.x + w / 2
    let top = center.y + h / 2, bottom = center.y - h / 2
    let r = h * 0.46   // bottom corner radius
    p.move(to: CGPoint(x: left - s, y: top))
    p.addLine(to: CGPoint(x: right + s, y: top))
    // right shoulder: concave quarter turn from the top edge down into the side
    p.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right, y: top - s), radius: s)
    p.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right - r, y: bottom), radius: r)
    p.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: bottom + r), radius: r)
    p.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left - s, y: top), radius: s)
    p.closeSubpath()
    return p
}

/// Three-blade fan centred at `c` with outer radius `R`, blades swept clockwise.
func fanPath(center c: CGPoint, radius R: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for k in 0..<3 {
        let a0 = CGFloat(k) * 2 * .pi / 3 + .pi / 2
        let blade = CGMutablePath()
        // a curved, teardrop-like blade from the hub to the rim
        blade.move(to: CGPoint(x: R * 0.10, y: R * 0.06))
        blade.addCurve(to: CGPoint(x: R * 0.88, y: R * 0.46),
                       control1: CGPoint(x: R * 0.30, y: R * 0.52),
                       control2: CGPoint(x: R * 0.62, y: R * 0.64))
        blade.addCurve(to: CGPoint(x: R * 0.86, y: -R * 0.20),
                       control1: CGPoint(x: R * 1.10, y: R * 0.30),
                       control2: CGPoint(x: R * 1.08, y: -R * 0.06))
        blade.addCurve(to: CGPoint(x: R * 0.10, y: -R * 0.06),
                       control1: CGPoint(x: R * 0.60, y: -R * 0.34),
                       control2: CGPoint(x: R * 0.30, y: -R * 0.18))
        blade.closeSubpath()
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a0)
        p.addPath(blade, transform: t)
        t = .identity
    }
    return p
}

// MARK: - Drawing

func drawIcon(in ctx: CGContext, size px: Int) {
    let k = CGFloat(px) / 1024
    ctx.saveGState()
    ctx.scaleBy(x: k, y: k)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    // Apple's continuous-corner rounded rect (SwiftUI's .continuous style), radius 185.4 on 824 —
    // the macOS icon grid. It must match the system mask: macOS 26 puts icons whose shape does not
    // match (e.g. a plain superellipse, tested) on a grey "legacy" platter in Finder and the Dock.
    let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: body).cgPath

    // grid drop shadow (macOS icon template: y −10, blur 20, black ~30 %)
    if px >= 64 {
        ctx.saveGState()
        // CG shadows are in device space: scale offset/blur with the canvas
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: rgb(0x000000, 0.30))
        ctx.addPath(shape); ctx.setFillColor(bgBottom); ctx.fillPath()
        ctx.restoreGState()
    }

    // background: two-tone graphite gradient + faint top light
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let g = CGGradient(colorsSpace: cs, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let light = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: 512, y: 1010), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 1010), endRadius: 620, options: [])
    ctx.restoreGState()

    // hairline edge highlight (top) — the subtle rim Apple's glyph icons have
    if px >= 128 {
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.addPath(shape)
        ctx.setLineWidth(4)
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // glyph (one white shape): a display outline whose top edge carries the notch, and a small fan
    // in the screen below it — the same "notch at the top of a screen" reading as the menu bar
    // symbol (rectangle.topthird.inset.filled).
    let screen = CGRect(x: 512 - 300, y: 512 - 215, width: 600, height: 430)
    let stroke: CGFloat = px >= 64 ? 34 : 44
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(glyph)
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 70, cornerHeight: 70, transform: nil))
    ctx.addPath(CGPath(roundedRect: screen.insetBy(dx: stroke, dy: stroke),
                       cornerWidth: 70 - stroke, cornerHeight: 70 - stroke, transform: nil))
    ctx.fillPath(using: .evenOdd)
    let innerTop = screen.maxY - stroke
    ctx.addPath(notchPath(center: CGPoint(x: 512, y: innerTop - 34 + 1), width: 220, height: 70, shoulder: 16))
    ctx.fillPath()
    if px >= 32 {
        ctx.addPath(fanPath(center: CGPoint(x: 512, y: 470), radius: 112))
        ctx.fillPath()
        // hub ring: knock a thin gap around the hub so the blades read as a fan at small sizes
        ctx.setBlendMode(.destinationOut)
        ctx.addEllipse(in: CGRect(x: 512 - 30, y: 470 - 30, width: 60, height: 60))
        ctx.fillPath()
        ctx.setBlendMode(.normal)
        ctx.addEllipse(in: CGRect(x: 512 - 20, y: 470 - 20, width: 40, height: 40))
        ctx.fillPath()
    }
    ctx.endTransparencyLayer()

    ctx.restoreGState()
}

func bitmap(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ img: CGImage, to url: URL, dpi: Int = 72) throws {
    let rep = NSBitmapImageRep(cgImage: img)
    let pts = Int(Double(img.width) * 72 / Double(dpi))
    rep.size = NSSize(width: pts, height: Int(Double(img.height) * 72 / Double(dpi)))
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func renderIcon(_ px: Int) -> CGImage {
    let ctx = bitmap(px, px)
    drawIcon(in: ctx, size: px)
    return ctx.makeImage()!
}

// MARK: - .iconset → .icns

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("DynamicNotchAppIcon-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try writePNG(renderIcon(base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(renderIcon(base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"), dpi: 144)
}
// 64 px is not part of the .iconset naming scheme (32@2x covers it); render it for the preview only.
let icns = supportDir.appendingPathComponent("DynamicNotchAppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run(); iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try? fm.removeItem(at: iconset)
print("wrote \(icns.path)")

// MARK: - Preview (2×)

let scale = 2
let W = 760, H = 420   // points
let pctx = bitmap(W * scale, H * scale)
pctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
// light half / dark half
pctx.setFillColor(rgb(0xF2F2F7)); pctx.fill(CGRect(x: 0, y: 0, width: W / 2, height: H))
pctx.setFillColor(rgb(0x1C1C1E)); pctx.fill(CGRect(x: W / 2, y: 0, width: W / 2, height: H))
for (i, x) in [30, 410].enumerated() {
    _ = i
    let big = renderIcon(256 * scale)
    pctx.draw(big, in: CGRect(x: x + 30, y: 130, width: 256, height: 256))
    var cx = CGFloat(x + 10)
    for s in [128, 64, 32, 16] {
        let img = renderIcon(s * scale)
        pctx.draw(img, in: CGRect(x: cx, y: 30 + CGFloat(96 - s) / 2, width: CGFloat(s), height: CGFloat(s)))
        cx += CGFloat(s) + 16
    }
}
// menu bar glyph (template SF Symbol used by the status item) in both appearances
func drawSymbol(_ name: String, at p: CGPoint, color: NSColor) {
    let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    else { return }
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true
    }
    let g = NSGraphicsContext(cgContext: pctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
    tinted.draw(in: CGRect(origin: p, size: sym.size))
    NSGraphicsContext.restoreGraphicsState()
}
drawSymbol("rectangle.topthird.inset.filled", at: CGPoint(x: 340, y: 395), color: .black)
drawSymbol("rectangle.topthird.inset.filled", at: CGPoint(x: 720, y: 395), color: .white)
try fm.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try writePNG(pctx.makeImage()!, to: previewURL, dpi: 144)
print("wrote \(previewURL.path)")
