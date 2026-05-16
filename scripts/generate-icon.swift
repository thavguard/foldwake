#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Resources/IconSource/foldwake-hinge-halo.png")
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
let output = root.appendingPathComponent("Resources/AppIcon.icns")

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

struct IconVariant {
    let name: String
    let pixels: Int
}

let variants = [
    IconVariant(name: "icon_16x16.png", pixels: 16),
    IconVariant(name: "icon_16x16@2x.png", pixels: 32),
    IconVariant(name: "icon_32x32.png", pixels: 32),
    IconVariant(name: "icon_32x32@2x.png", pixels: 64),
    IconVariant(name: "icon_128x128.png", pixels: 128),
    IconVariant(name: "icon_128x128@2x.png", pixels: 256),
    IconVariant(name: "icon_256x256.png", pixels: 256),
    IconVariant(name: "icon_256x256@2x.png", pixels: 512),
    IconVariant(name: "icon_512x512.png", pixels: 512),
    IconVariant(name: "icon_512x512@2x.png", pixels: 1024)
]

guard let sourceImage = NSImage(contentsOf: source) else {
    throw NSError(
        domain: "FoldwakeIcon",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not read \(source.path)"]
    )
}

func render(_ image: NSImage, pixels: Int) throws -> Data {
    let size = NSSize(width: pixels, height: pixels)
    let resized = NSImage(size: size)
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(origin: .zero, size: size),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    resized.unlockFocus()

    guard
        let tiff = resized.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "FoldwakeIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not render \(pixels)px icon"]
        )
    }
    return png
}

for variant in variants {
    try render(sourceImage, pixels: variant.pixels)
        .write(to: iconset.appendingPathComponent(variant.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(
        domain: "FoldwakeIcon",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed"]
    )
}

print(output.path)
