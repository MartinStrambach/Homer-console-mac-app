// Writes App/HomerConsole/Assets.xcassets/AppIcon.appiconset: the console's SF Symbol
// (`HomerSymbols.console`, waveform.path.ecg) in white on a blue-to-teal rounded square, at
// every size macOS asks for.
//
//   swift scripts/make-icon.swift
//
// Rerun it after changing the drawing below.

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appending(path: "App/HomerConsole/Assets.xcassets/AppIcon.appiconset")

/// The 1024 pt master, on macOS's icon grid: an 824 pt rounded square centred in the canvas,
/// leaving room for the shadow the system draws.
func master() -> NSImage {
	let size = NSSize(width: 1024, height: 1024)
	return NSImage(size: size, flipped: false) { _ in
		let body = NSRect(x: 100, y: 100, width: 824, height: 824)
		let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

		NSGraphicsContext.saveGraphicsState()
		let shadow = NSShadow()
		shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
		shadow.shadowOffset = NSSize(width: 0, height: -12)
		shadow.shadowBlurRadius = 28
		shadow.set()
		NSColor.black.setFill()
		path.fill()
		NSGraphicsContext.restoreGraphicsState()

		NSGradient(
			starting: NSColor(srgbRed: 0.13, green: 0.36, blue: 0.86, alpha: 1),
			ending: NSColor(srgbRed: 0.05, green: 0.68, blue: 0.66, alpha: 1)
		)?.draw(in: path, angle: -60)

		let configuration = NSImage.SymbolConfiguration(pointSize: 470, weight: .semibold)
			.applying(.init(paletteColors: [.white]))
		if let symbol = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)?
			.withSymbolConfiguration(configuration) {
			let symbolSize = symbol.size
			symbol.draw(in: NSRect(
				x: body.midX - symbolSize.width / 2,
				y: body.midY - symbolSize.height / 2,
				width: symbolSize.width,
				height: symbolSize.height
			))
		}
		return true
	}
}

func png(_ image: NSImage, pixels: Int) -> Data {
	let rep = NSBitmapImageRep(
		bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
		samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
		bytesPerRow: 0, bitsPerPixel: 0
	)!
	rep.size = NSSize(width: pixels, height: pixels)
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
	NSGraphicsContext.restoreGraphicsState()
	return rep.representation(using: .png, properties: [:])!
}

let image = master()
try? FileManager.default.removeItem(at: iconSet)
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
	for scale in [1, 2] {
		let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
		try png(image, pixels: points * scale).write(to: iconSet.appending(path: name))
		entries.append("""
		    { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
		""")
	}
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
try """
{
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: iconSet.deletingLastPathComponent().appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(iconSet.path)")
