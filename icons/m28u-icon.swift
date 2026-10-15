// M28U-style icon with a heavily compressed "MB" screen.
// swiftc -O -o /tmp/m28u-icon icons/m28u-icon.swift && /tmp/m28u-icon <out dir>
import AppKit
import CoreImage
import SwiftUI

let canvas: CGFloat = 1024
let tile: CGFloat = 824
let corner: CGFloat = 185
let orange = Color(red: 1.0, green: 0.42, blue: 0.08)

// Panel geometry, modelled on the M28U: thin bezels, thicker chin.
let frameWidth: CGFloat = 700
let bezel: CGFloat = 11
let chin: CGFloat = 30
let screenSize = CGSize(width: frameWidth - bezel * 2, height: (frameWidth - bezel * 2) * 9 / 16)

/// What the panel shows before compression: AORUS-style orange wings and a big MB.
struct ScreenArt: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.13), Color(red: 0.03, green: 0.03, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                // Wing feathers: long slanted bars fanning out from the right.
                let origin = CGPoint(x: size.width * 0.7, y: size.height * 0.46)
                for i in 0..<7 {
                    let angle = Double(i - 3) * 0.13
                    let length = size.width * (0.62 - Double(abs(i - 3)) * 0.05)
                    var bar = Path()
                    bar.addRoundedRect(in: CGRect(x: -length, y: -9, width: length, height: 18), cornerSize: CGSize(width: 9, height: 9))
                    let transform = CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: angle)
                    context.fill(bar.applying(transform), with: .color(orange.opacity(0.95 - Double(abs(i - 3)) * 0.12)))
                }
            }
            Text("MB")
                .font(.system(size: 230, weight: .black, design: .default))
                .tracking(-6)
                .foregroundStyle(.white)
                .offset(x: 40, y: 6)
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}

enum Compression {
    case jpeg(scale: CGFloat, quality: CGFloat)
    case blur(radius: CGFloat)
    case pixels(scale: CGFloat)
    case crushed(width: Int)
}

func resizeImage(_ image: CGImage, to target: CGSize, smooth: Bool) -> CGImage {
    let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = smooth ? .medium : .none
    context.draw(image, in: CGRect(origin: .zero, size: target))
    return context.makeImage()!
}

func jpegRoundTrip(_ image: CGImage, quality: CGFloat) -> CGImage {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: quality])!
    return NSBitmapImageRep(data: data)!.cgImage!
}

/// The "4K badge" treatment: shrink to a few dozen pixels, JPEG it, enlarge 4x, JPEG it
/// again (generation loss), then stretch to full size with soft interpolation.
func crush(_ image: CGImage, width: Int) -> CGImage {
    let full = CGSize(width: image.width, height: image.height)
    let tiny = CGSize(width: CGFloat(width), height: (CGFloat(width) * full.height / full.width).rounded())
    var out = jpegRoundTrip(resizeImage(image, to: tiny, smooth: true), quality: 0.25)
    out = resizeImage(out, to: CGSize(width: tiny.width * 4, height: tiny.height * 4), smooth: false)
    out = jpegRoundTrip(out, quality: 0.18)
    out = resizeImage(out, to: CGSize(width: tiny.width * 8, height: tiny.height * 8), smooth: true)
    out = jpegRoundTrip(out, quality: 0.3)
    return resizeImage(out, to: full, smooth: true)
}

@MainActor
func screenImage(_ compression: Compression) -> NSImage {
    let renderer = ImageRenderer(content: ScreenArt())
    renderer.scale = 1
    let full = renderer.cgImage!
    let size = CGSize(width: full.width, height: full.height)

    func resize(_ image: CGImage, to target: CGSize, smooth: Bool) -> CGImage {
        let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = smooth ? .high : .none
        context.draw(image, in: CGRect(origin: .zero, size: target))
        return context.makeImage()!
    }

    switch compression {
    case let .jpeg(scale, quality):
        // Shrink, save as a very low quality JPEG, decode, blow back up.
        let small = resize(full, to: CGSize(width: size.width * scale, height: size.height * scale), smooth: true)
        let data = NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: quality])!
        let decoded = NSBitmapImageRep(data: data)!.cgImage!
        let up = resize(decoded, to: size, smooth: true)
        return NSImage(cgImage: up, size: size)
    case let .pixels(scale):
        let small = resize(full, to: CGSize(width: size.width * scale, height: size.height * scale), smooth: true)
        return NSImage(cgImage: resize(small, to: size, smooth: false), size: size)
    case let .crushed(width):
        return NSImage(cgImage: crush(full, width: width), size: size)
    case let .blur(radius):
        let input = CIImage(cgImage: full).clampedToExtent()
        let output = input.applyingGaussianBlur(sigma: radius).cropped(to: CGRect(origin: .zero, size: size))
        return NSImage(cgImage: CIContext().createCGImage(output, from: output.extent)!, size: size)
    }
}

struct Monitor: View {
    let screen: NSImage

    var body: some View {
        let frameHeight = bezel + screenSize.height + chin
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.07))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(white: 0.2), lineWidth: 2))
                Image(nsImage: screen)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: screenSize.width + 6, height: screenSize.height + 6)
                    .frame(width: screenSize.width, height: screenSize.height)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color(red: 0.03, green: 0.03, blue: 0.05)).frame(height: 8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.top, bezel)
                // Logo spot on the chin.
                Capsule()
                    .fill(Color(white: 0.32))
                    .frame(width: 70, height: 7)
                    .offset(y: frameHeight - chin / 2 - 3.5)
            }
            .frame(width: frameWidth, height: frameHeight)
            Stand()
        }
    }
}

/// Narrow post with a cable hole, on a low base with two splayed legs.
struct Stand: View {
    var body: some View {
        ZStack(alignment: .top) {
            Canvas { context, size in
                let mid = size.width / 2
                let postTop: CGFloat = 0, postBottom: CGFloat = 112
                var post = Path(roundedRect: CGRect(x: mid - 32, y: postTop, width: 64, height: postBottom), cornerRadius: 6)
                post.addRoundedRect(in: CGRect(x: mid - 15, y: 20, width: 30, height: 22), cornerSize: CGSize(width: 7, height: 7))
                context.fill(post, with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.1)]),
                                                         startPoint: CGPoint(x: mid - 32, y: 0), endPoint: CGPoint(x: mid + 32, y: 0)),
                             style: FillStyle(eoFill: true))
                var base = Path()
                let y = postBottom - 6
                base.move(to: CGPoint(x: mid - 70, y: y))
                base.addLine(to: CGPoint(x: mid + 70, y: y))
                base.addLine(to: CGPoint(x: mid + 255, y: y + 38))
                base.addLine(to: CGPoint(x: mid + 240, y: y + 50))
                base.addLine(to: CGPoint(x: mid + 40, y: y + 24))
                base.addLine(to: CGPoint(x: mid - 40, y: y + 24))
                base.addLine(to: CGPoint(x: mid - 240, y: y + 50))
                base.addLine(to: CGPoint(x: mid - 255, y: y + 38))
                base.closeSubpath()
                context.fill(base, with: .color(Color(white: 0.12)))
                context.stroke(base, with: .color(Color(white: 0.26)), lineWidth: 1.5)
            }
        }
        .frame(width: 560, height: 170)
    }
}

struct Icon: View {
    let background: AnyShapeStyle
    let screen: NSImage

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(background)
                .frame(width: tile, height: tile)
            Monitor(screen: screen)
                .offset(y: 30)
        }
        .frame(width: tile, height: tile)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .frame(width: canvas, height: canvas)
    }
}

@MainActor
func png(_ view: some View, _ url: URL, scale: CGFloat = 1) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    if let cg = renderer.cgImage {
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
    }
}

MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    let light = AnyShapeStyle(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.84)], startPoint: .top, endPoint: .bottom))
    let warm = AnyShapeStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.2), Color(red: 0.93, green: 0.36, blue: 0.08)],
                                            startPoint: .top, endPoint: .bottom))
    let graphite = AnyShapeStyle(Color(white: 0.22))

    @MainActor func crushedIcon(_ width: Int) -> AnyView {
        let renderer = ImageRenderer(content: Icon(background: warm, screen: screenImage(.blur(radius: 0.01))))
        renderer.scale = 1
        let image = crush(renderer.cgImage!, width: width)
        return AnyView(Image(nsImage: NSImage(cgImage: image, size: CGSize(width: canvas, height: canvas)))
            .resizable().frame(width: canvas, height: canvas)
            .mask(RoundedRectangle(cornerRadius: corner, style: .continuous).frame(width: tile, height: tile)))
    }
    let variants: [(String, AnyView)] = [
        ("1  Screen, mild (72 px)", AnyView(Icon(background: warm, screen: screenImage(.crushed(width: 72))))),
        ("2  Screen, strong (48 px)", AnyView(Icon(background: warm, screen: screenImage(.crushed(width: 48))))),
        ("3  Screen, extreme (32 px)", AnyView(Icon(background: warm, screen: screenImage(.crushed(width: 32))))),
        ("4  Strong, light tile", AnyView(Icon(background: light, screen: screenImage(.crushed(width: 48))))),
        ("5  Whole icon (96 px)", crushedIcon(96)),
        ("6  Whole icon (64 px)", crushedIcon(64)),
    ]
    _ = graphite
    for (i, variant) in variants.enumerated() {
        png(variant.1, out.appendingPathComponent("crushed-\(i + 1).png"))
    }
    let sheet = VStack(alignment: .leading, spacing: 34) {
        ForEach([0, 3], id: \.self) { start in
            HStack(alignment: .top, spacing: 40) {
                ForEach(start..<start + 3, id: \.self) { i in
                    VStack(spacing: 12) {
                        variants[i].1.scaleEffect(0.3).frame(width: 307, height: 307)
                        Text(variants[i].0).font(.system(size: 20, weight: .semibold))
                        HStack(alignment: .bottom, spacing: 16) {
                            variants[i].1.scaleEffect(64 / canvas).frame(width: 64, height: 64)
                            variants[i].1.scaleEffect(32 / canvas).frame(width: 32, height: 32)
                            variants[i].1.scaleEffect(16 / canvas).frame(width: 16, height: 16)
                        }
                    }
                }
            }
        }
    }
    .padding(40)
    .background(Color(white: 0.93))
    png(sheet, out.appendingPathComponent("crushed-sheet.png"))
}
