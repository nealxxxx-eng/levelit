#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let f: CGFloat = size / 256

// MARK: - PNG 保存

func savePNG(_ context: CGContext, to path: String) {
    guard let image = context.makeImage() else {
        print("Failed to create image")
        return
    }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("Failed to create destination: \(path)")
        return
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("Saved: \(path)")
}

func makeContext() -> CGContext {
    let cs = CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

// MARK: - Color helpers

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> [CGFloat] {
    [r/255, g/255, b/255, a]
}

func lerpColor(_ c1: [CGFloat], _ c2: [CGFloat], _ t: CGFloat) -> [CGFloat] {
    (0..<4).map { c1[$0] + (c2[$0] - c1[$0]) * t }
}

// MARK: - Rounded rect

func addRoundedRect(_ ctx: CGContext, _ rect: CGRect, _ radius: CGFloat) {
    ctx.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
    ctx.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    ctx.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
    ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    ctx.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
    ctx.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    ctx.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
    ctx.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    ctx.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
    ctx.closePath()
}

// MARK: - Radial glow

func drawRadialGlow(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, color: [CGFloat], alpha: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(colorSpace: cs, components: [color[0]/255, color[1]/255, color[2]/255, alpha])!,
        CGColor(colorSpace: cs, components: [color[0]/255, color[1]/255, color[2]/255, alpha * 0.3])!,
        CGColor(colorSpace: cs, components: [color[0]/255, color[1]/255, color[2]/255, 0])!,
    ] as CFArray
    let locs: [CGFloat] = [0, 0.5, 1]
    if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
        ctx.drawRadialGradient(grad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy), endRadius: radius, options: [])
    }
}

// MARK: - Progress ring (segmented for gradient effect)

func drawProgressRing(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, lineWidth: CGFloat, progress: CGFloat) {
    let startAngle = CGFloat.pi * 0.5  // top in flipped coords
    let segments = 120
    let totalArc = CGFloat.pi * 2 * progress

    // Background track
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.06))
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Gradient colors along arc: gold → orange → deep orange
    let colors: [[CGFloat]] = [
        [255, 204, 2],     // gold
        [255, 149, 0],     // orange
        [255, 123, 0],     // deep orange
        [255, 85, 0],      // red-orange
    ]

    for i in 0..<segments {
        let t0 = CGFloat(i) / CGFloat(segments)
        let t1 = CGFloat(i + 1) / CGFloat(segments)

        // Interpolate color
        let colorT = t0
        let segIdx = min(Int(colorT * CGFloat(colors.count - 1)), colors.count - 2)
        let localT = colorT * CGFloat(colors.count - 1) - CGFloat(segIdx)
        let c = lerpColor(
            rgb(colors[segIdx][0], colors[segIdx][1], colors[segIdx][2]),
            rgb(colors[segIdx+1][0], colors[segIdx+1][1], colors[segIdx+1][2]),
            localT
        )

        let a0 = startAngle - t0 * totalArc
        let a1 = startAngle - t1 * totalArc

        ctx.setStrokeColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: c)!)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(i == 0 || i == segments - 1 ? .round : .butt)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
        ctx.strokePath()
    }

    // End cap glow
    let endAngle = startAngle - totalArc
    let dotX = cx + radius * cos(endAngle)
    let dotY = cy + radius * sin(endAngle)
    drawRadialGlow(ctx, cx: dotX, cy: dotY, radius: 20 * f, color: [255, 85, 0], alpha: 0.35)
}

// MARK: - Flame

func drawFlame(_ ctx: CGContext, cx: CGFloat, baseY: CGFloat, height: CGFloat) {
    // Note: CoreGraphics Y is flipped (0 at bottom), but our context is top-down
    // We'll draw in "screen" coordinates where Y increases downward

    // Glow beneath flame
    drawRadialGlow(ctx, cx: cx, cy: baseY - height * 0.2, radius: height * 0.6, color: [255, 120, 0], alpha: 0.15)

    // Outer flame path
    func flamePath(h: CGFloat, widthFactor: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx, y: baseY))
        // Left side
        path.addCurve(
            to: CGPoint(x: cx - h * 0.30, y: baseY - h * 0.72),
            control1: CGPoint(x: cx - h * widthFactor, y: baseY - h * 0.08),
            control2: CGPoint(x: cx - h * (widthFactor + 0.12), y: baseY - h * 0.42)
        )
        // Left tip
        path.addCurve(
            to: CGPoint(x: cx, y: baseY - h * 1.02),
            control1: CGPoint(x: cx - h * 0.18, y: baseY - h * 0.88),
            control2: CGPoint(x: cx - h * 0.08, y: baseY - h * 0.97)
        )
        // Right tip
        path.addCurve(
            to: CGPoint(x: cx + h * 0.30, y: baseY - h * 0.72),
            control1: CGPoint(x: cx + h * 0.08, y: baseY - h * 0.97),
            control2: CGPoint(x: cx + h * 0.18, y: baseY - h * 0.88)
        )
        // Right side
        path.addCurve(
            to: CGPoint(x: cx, y: baseY),
            control1: CGPoint(x: cx + h * (widthFactor + 0.12), y: baseY - h * 0.42),
            control2: CGPoint(x: cx + h * widthFactor, y: baseY - h * 0.08)
        )
        path.closeSubpath()
        return path
    }

    let cs = CGColorSpaceCreateDeviceRGB()

    // Outer flame
    let outerPath = flamePath(h: height, widthFactor: 0.38)
    ctx.saveGState()
    ctx.addPath(outerPath)
    ctx.clip()
    let outerColors = [
        CGColor(colorSpace: cs, components: [1, 0.33, 0, 1])!,      // #FF5500
        CGColor(colorSpace: cs, components: [1, 0.48, 0, 1])!,      // #FF7B00
        CGColor(colorSpace: cs, components: [1, 0.58, 0, 1])!,      // #FF9500
        CGColor(colorSpace: cs, components: [1, 0.73, 0, 1])!,      // #FFBB00
        CGColor(colorSpace: cs, components: [1, 0.87, 0.27, 1])!,   // #FFDD44
    ] as CFArray
    let outerLocs: [CGFloat] = [0, 0.3, 0.6, 0.85, 1]
    if let g = CGGradient(colorsSpace: cs, colors: outerColors, locations: outerLocs) {
        ctx.drawLinearGradient(g, start: CGPoint(x: cx, y: baseY), end: CGPoint(x: cx, y: baseY - height), options: [])
    }
    ctx.restoreGState()

    // Mid flame
    let midH = height * 0.65
    let midPath = flamePath(h: midH, widthFactor: 0.35)
    ctx.saveGState()
    ctx.addPath(midPath)
    ctx.clip()
    let midColors = [
        CGColor(colorSpace: cs, components: [1, 0.72, 0.2, 1])!,    // #FFB833
        CGColor(colorSpace: cs, components: [1, 0.80, 0.27, 1])!,   // #FFCC44
        CGColor(colorSpace: cs, components: [1, 0.90, 0.47, 1])!,   // #FFE577
    ] as CFArray
    let midLocs: [CGFloat] = [0, 0.5, 1]
    if let g = CGGradient(colorsSpace: cs, colors: midColors, locations: midLocs) {
        ctx.drawLinearGradient(g, start: CGPoint(x: cx, y: baseY), end: CGPoint(x: cx, y: baseY - midH), options: [])
    }
    ctx.restoreGState()

    // Inner flame (bright core)
    let innerH = height * 0.38
    let innerPath = flamePath(h: innerH, widthFactor: 0.32)
    ctx.saveGState()
    ctx.addPath(innerPath)
    ctx.clip()
    let innerColors = [
        CGColor(colorSpace: cs, components: [1, 0.95, 0.83, 1])!,   // #FFF3D4
        CGColor(colorSpace: cs, components: [1, 0.93, 0.74, 1])!,   // #FFEEBC
        CGColor(colorSpace: cs, components: [1, 0.88, 0.53, 1])!,   // #FFE088
    ] as CFArray
    let innerLocs: [CGFloat] = [0, 0.4, 1]
    if let g = CGGradient(colorsSpace: cs, colors: innerColors, locations: innerLocs) {
        ctx.drawLinearGradient(g, start: CGPoint(x: cx, y: baseY), end: CGPoint(x: cx, y: baseY - innerH), options: [])
    }
    ctx.restoreGState()
}

// MARK: - Draw full icon

func drawIcon(_ ctx: CGContext, mode: String) {
    let s = size
    let cx = s * 0.5
    let cy = s * 0.5
    let cs = CGColorSpaceCreateDeviceRGB()

    // Background
    ctx.saveGState()
    let bgColors: ([CGFloat], [CGFloat])
    switch mode {
    case "dark":
        bgColors = (rgb(10, 10, 12), rgb(0, 0, 0))
    case "tinted":
        bgColors = (rgb(26, 21, 16), rgb(15, 12, 8))
    default: // light & watch
        bgColors = (rgb(30, 30, 34), rgb(17, 17, 19))
    }

    if mode == "watch" {
        // Circular clip for watch
        ctx.addEllipse(in: CGRect(x: 0, y: 0, width: s, height: s))
        ctx.clip()
    }

    addRoundedRect(ctx, CGRect(x: 0, y: 0, width: s, height: s), 56 * f)
    ctx.clip()

    // Background gradient
    let bgCols = [
        CGColor(colorSpace: cs, components: bgColors.0)!,
        CGColor(colorSpace: cs, components: bgColors.1)!,
    ] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: bgCols, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s * 0.3, y: s), options: [.drawsAfterEndLocation])
    }

    // Ambient glow
    drawRadialGlow(ctx, cx: cx, cy: cy * 0.9, radius: s * 0.45, color: [255, 149, 0], alpha: 0.10)

    // Progress ring
    let radius = s * 0.34
    let ringWidth: CGFloat = 14 * f
    drawProgressRing(ctx, cx: cx, cy: cy, radius: radius, lineWidth: ringWidth, progress: 0.78)

    // Center flame
    drawFlame(ctx, cx: cx, baseY: cy + s * 0.07, height: s * 0.24)

    ctx.restoreGState()
}

// MARK: - Generate all icons

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let variants = ["light", "dark", "tinted", "watch"]
for mode in variants {
    let ctx = makeContext()
    drawIcon(ctx, mode: mode)
    let suffix = mode == "light" ? "" : "_\(mode)"
    savePNG(ctx, to: "\(outputDir)/AppIcon\(suffix).png")
}

print("Done! Generated \(variants.count) icons.")
