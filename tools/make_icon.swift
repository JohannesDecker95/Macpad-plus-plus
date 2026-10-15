// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>
// Renders a macOS style app icon (1024x1024 PNG): the logo centred on a rounded white tile
// following Apple's icon grid (824pt tile, 100pt margin, ~185pt corner radius).
// usage: swift make_icon.swift <logo image> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
	FileHandle.standardError.write("usage: make_icon.swift <logo image> <out.png>\n".data(using: .utf8)!)
	exit(1)
}

let size = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Tile colour = the logo's corner pixel, so the logo's own background blends in
var paper = NSColor.white
if let cg = logo.cgImage(forProposedRect: nil, context: nil, hints: nil),
   let c = NSBitmapImageRep(cgImage: cg).colorAt(x: 2, y: 2) { paper = c }

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 20
NSGraphicsContext.saveGraphicsState()
shadow.set()
paper.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

// Fit the logo inside the tile with some padding, keeping its aspect ratio
path.addClip()
let box = tile.insetBy(dx: 70, dy: 70)
let ls = logo.size
let scale = min(box.width / ls.width, box.height / ls.height)
let w = ls.width * scale, h = ls.height * scale
logo.draw(in: NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
