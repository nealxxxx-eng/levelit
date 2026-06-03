#!/usr/bin/env swift
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// iPhone 6.7" required: 1290 x 2796
let W: CGFloat = 1290
let H: CGFloat = 2796

func makeContext(_ w: CGFloat = W, _ h: CGFloat = H) -> CGContext {
    CGContext(
        data: nil, width: Int(w), height: Int(h),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func savePNG(_ ctx: CGContext, _ path: String) {
    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("Saved: \(path)")
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - Drawing helpers

func drawText(_ ctx: CGContext, text: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = true, color: CGColor = CGColor(gray: 1, alpha: 1), maxWidth: CGFloat = 0) {
    let font = CTFontCreateWithName((bold ? "PingFangSC-Semibold" : "PingFangSC-Regular") as CFString, size, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
    ]
    let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!

    let line = CTLineCreateWithAttributedString(attrStr)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

func drawRoundedRect(_ ctx: CGContext, rect: CGRect, radius: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.fillPath()
}

// MARK: - Marketing screenshot background

func drawBackground(_ ctx: CGContext, gradient: [(CGFloat, CGFloat, CGFloat)]) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = gradient.map { CGColor(colorSpace: cs, components: [$0.0, $0.1, $0.2, 1])! } as CFArray
    let locs: [CGFloat] = gradient.count == 2 ? [0, 1] : [0, 0.5, 1]
    if let g = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
        ctx.drawLinearGradient(g, start: CGPoint(x: W/2, y: H), end: CGPoint(x: W/2, y: 0), options: [.drawsAfterEndLocation])
    }
}

func drawScreenshot(_ ctx: CGContext, image: CGImage, yOffset: CGFloat) {
    // Draw device screenshot with rounded corners and shadow
    let screenW: CGFloat = 1050
    let screenH: CGFloat = screenW * CGFloat(image.height) / CGFloat(image.width)
    let screenX = (W - screenW) / 2
    let screenY = yOffset
    let cornerRadius: CGFloat = 60

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: CGColor(gray: 0, alpha: 0.4))
    drawRoundedRect(ctx, rect: CGRect(x: screenX, y: screenY, width: screenW, height: screenH), radius: cornerRadius, color: CGColor(gray: 0, alpha: 1))
    ctx.restoreGState()

    // Clipped screenshot
    ctx.saveGState()
    let clipRect = CGRect(x: screenX, y: screenY, width: screenW, height: screenH)
    let clipPath = CGPath(roundedRect: clipRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()
    ctx.draw(image, in: clipRect)
    ctx.restoreGState()
}

// MARK: - Generate screenshots

let baseDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let screenshotDir = baseDir + "/screenshots"

// Load the home screenshot
guard let homeImg = loadImage("\(screenshotDir)/01_home.png") else {
    print("Error: Cannot load 01_home.png")
    exit(1)
}

let cs = CGColorSpaceCreateDeviceRGB()
let white = CGColor(gray: 1, alpha: 1)
let white80 = CGColor(gray: 1, alpha: 0.8)
let orange = CGColor(colorSpace: cs, components: [1, 0.58, 0, 1])!

// Screenshot 1: Home - "拍一下食物，看看你得动多久"
do {
    let ctx = makeContext()
    drawBackground(ctx, gradient: [(0.08, 0.08, 0.10), (0.15, 0.08, 0.04)])

    // Headline - note: CoreGraphics Y is from bottom
    drawText(ctx, text: "拍一下食物", x: 120, y: H - 180, size: 80, color: white)
    drawText(ctx, text: "看看你得动多久", x: 120, y: H - 290, size: 80, color: orange)

    // Subtitle
    drawText(ctx, text: "AI 估算热量，Apple Watch 实时运动", x: 120, y: H - 400, size: 36, bold: false, color: white80)

    // Screenshot
    drawScreenshot(ctx, image: homeImg, yOffset: 80)

    savePNG(ctx, "\(screenshotDir)/AppStore_01.png")
}

// Screenshot 2: Task detail - "每一口都有代价"
do {
    let ctx = makeContext()
    drawBackground(ctx, gradient: [(0.06, 0.06, 0.12), (0.04, 0.10, 0.08)])

    drawText(ctx, text: "每一口", x: 120, y: H - 180, size: 80, color: white)
    drawText(ctx, text: "都有代价", x: 120, y: H - 290, size: 80, color: orange)
    drawText(ctx, text: "创建热量债务，用运动来磨平", x: 120, y: H - 400, size: 36, bold: false, color: white80)

    drawScreenshot(ctx, image: homeImg, yOffset: 80)

    savePNG(ctx, "\(screenshotDir)/AppStore_02.png")
}

// Screenshot 3: Watch + Stats concept - "实时追踪"
do {
    let ctx = makeContext()
    drawBackground(ctx, gradient: [(0.10, 0.06, 0.02), (0.06, 0.04, 0.10)])

    drawText(ctx, text: "Apple Watch", x: 120, y: H - 180, size: 72, color: white)
    drawText(ctx, text: "实时运动追踪", x: 120, y: H - 280, size: 72, color: orange)
    drawText(ctx, text: "12种运动 · HealthKit驱动 · 心率实时监测", x: 120, y: H - 380, size: 34, bold: false, color: white80)

    // Feature list
    let features = [
        ("figure.run", "跑步、骑行、游泳等 12 种运动"),
        ("heart.fill", "实时心率和卡路里追踪"),
        ("trophy.fill", "磨平动画 + 战绩分享卡"),
        ("chart.bar.fill", "周/月统计一目了然"),
    ]

    let featureY: CGFloat = 1500
    for (i, feature) in features.enumerated() {
        let y = featureY - CGFloat(i) * 180
        // Feature background
        drawRoundedRect(ctx, rect: CGRect(x: 100, y: y - 30, width: W - 200, height: 140), radius: 20,
                       color: CGColor(gray: 1, alpha: 0.06))
        drawText(ctx, text: feature.1, x: 160, y: y + 30, size: 40, bold: false, color: white80)
    }

    savePNG(ctx, "\(screenshotDir)/AppStore_03.png")
}

// Screenshot 4: Achievement / brand - "磨平，不只是记账"
do {
    let ctx = makeContext()
    drawBackground(ctx, gradient: [(0.04, 0.04, 0.08), (0.12, 0.06, 0.02)])

    // Large centered branding
    drawText(ctx, text: "磨平", x: W/2 - 120, y: H/2 + 200, size: 120, color: orange)
    drawText(ctx, text: "不只是记账", x: W/2 - 200, y: H/2 + 50, size: 72, color: white)
    drawText(ctx, text: "是行为改变系统", x: W/2 - 200, y: H/2 - 50, size: 72, color: white80)

    // Stats summary
    let statsY: CGFloat = H/2 - 250
    let statItems = [("3+", "连续磨平"), ("1,634", "待消耗 kcal"), ("12", "运动模式")]
    let statW: CGFloat = 350
    for (i, item) in statItems.enumerated() {
        let x: CGFloat = 80 + CGFloat(i) * (statW + 30)
        drawRoundedRect(ctx, rect: CGRect(x: x, y: statsY - 20, width: statW, height: 160), radius: 20,
                       color: CGColor(gray: 1, alpha: 0.06))
        drawText(ctx, text: item.0, x: x + statW/2 - 60, y: statsY + 80, size: 52, color: orange)
        drawText(ctx, text: item.1, x: x + statW/2 - 60, y: statsY + 20, size: 28, bold: false, color: white80)
    }

    // Bottom tagline
    drawText(ctx, text: "表盘 Complication · 成就徽章 · 每日提醒", x: 200, y: 300, size: 32, bold: false, color: CGColor(gray: 1, alpha: 0.4))

    savePNG(ctx, "\(screenshotDir)/AppStore_04.png")
}

print("Done! Generated 4 marketing screenshots.")
