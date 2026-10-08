// Writes App/HomerConsole/Assets.xcassets/AppIcon.appiconset: Homer taking a bite out of the
// rainbow Apple logo, under Springfield's sky, at every size macOS asks for; AppIconDebug.appiconset,
// the same icon with a red "DEBUG" ribbon across its top-right corner, which the Debug
// configuration uses; and the drawing without the icon grid's margin and shadow as
// Sources/HomerUI/Resources/HomerLogo.png, the logo the console's views show (`HomerLogo`).
//
//   swift scripts/make-icon.swift
//
// Rerun it after changing the drawing below.

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appending(path: "App/HomerConsole/Assets.xcassets")
let logoFile = root.appending(path: "Sources/HomerUI/Resources/HomerLogo.png")

/// The 1024 pt master, on macOS's icon grid: an 824 pt rounded square centred in the canvas,
/// leaving room for the shadow the system draws. Drawn top-down (y grows downwards). `debug` adds
/// the Debug configuration's ribbon.
func master(debug: Bool) -> NSImage {
	let size = NSSize(width: 1024, height: 1024)
	return NSImage(size: size, flipped: true) { _ in
		let context = NSGraphicsContext.current!.cgContext
		let body = CGRect(x: 100, y: 100, width: 824, height: 824)
		let square = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

		context.saveGState()
		context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
		context.addPath(square)
		context.setFillColor(NSColor.black.cgColor)
		context.fillPath()
		context.restoreGState()

		drawContent(in: context, clippedTo: square, body: body)
		if debug {
			drawDebugRibbon(in: context, clippedTo: square, body: body)
		}
		return true
	}
}

/// The rounded square alone, filling the image: the master's 824 pt body, without the margin
/// and shadow of the icon grid.
func logo() -> NSImage {
	NSImage(size: NSSize(width: 824, height: 824), flipped: true) { _ in
		let context = NSGraphicsContext.current!.cgContext
		context.translateBy(x: -100, y: -100)
		let body = CGRect(x: 100, y: 100, width: 824, height: 824)
		let square = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
		drawContent(in: context, clippedTo: square, body: body)
		return true
	}
}

func drawContent(in context: CGContext, clippedTo square: CGPath, body: CGRect) {
	context.saveGState()
	context.addPath(square)
	context.clip()
	drawSky(in: context, body: body)
	drawHomer(in: context)
	drawApple(in: context, origin: CGPoint(x: 654, y: 444), width: 224)
	drawHand(in: context)
	context.restoreGState()
}

/// A red band reading "DEBUG" across the body's top-right corner, so a debug build is told apart
/// from the release app in the Dock and the app switcher. Its ends run off the rounded square.
func drawDebugRibbon(in context: CGContext, clippedTo square: CGPath, body: CGRect) {
	// The band's centre line runs from `offset` left of the corner to `offset` below it.
	let offset = body.width * 0.36, thickness = body.width * 0.12
	let length = offset * 2.squareRoot() + thickness * 2
	let strip = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
	let edge = thickness / 14

	context.saveGState()
	context.addPath(square)
	context.clip()
	context.translateBy(x: body.maxX - offset / 2, y: body.minY + offset / 2)
	context.rotate(by: .pi / 4)
	context.saveGState()
	context.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: NSColor.black.withAlphaComponent(0.35).cgColor)
	context.setFillColor(rgb(0xD62828))
	context.fill(strip)
	context.restoreGState()
	context.setFillColor(NSColor.white.withAlphaComponent(0.43).cgColor)
	context.fill(CGRect(x: strip.minX, y: strip.minY, width: length, height: edge))
	context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
	context.fill(CGRect(x: strip.minX, y: strip.maxY - edge, width: length, height: edge))

	let text = NSAttributedString(string: "DEBUG", attributes: [
		.font: NSFont.systemFont(ofSize: thickness * 0.62, weight: .heavy),
		.foregroundColor: NSColor.white,
	])
	let size = text.size()
	text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
	context.restoreGState()
}

func rgb(_ hex: UInt32) -> CGColor {
	NSColor(
		srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
		blue: CGFloat(hex & 0xFF) / 255, alpha: 1
	).cgColor
}

let ink = rgb(0x1A1A1A)
let skin = rgb(0xFED90F)
let stubble = rgb(0xD1B271)
let mouthInside = rgb(0x6B1D1D)
let tongueColor = rgb(0xE5737A)
let lineWidth: CGFloat = 7

func fill(_ path: CGPath, _ color: CGColor, in context: CGContext) {
	context.addPath(path)
	context.setFillColor(color)
	context.fillPath()
}

func stroke(_ path: CGPath, in context: CGContext, width: CGFloat = lineWidth, color: CGColor = ink) {
	context.addPath(path)
	context.setStrokeColor(color)
	context.setLineWidth(width)
	context.setLineCap(.round)
	context.setLineJoin(.round)
	context.strokePath()
}

func fillAndStroke(_ path: CGPath, _ color: CGColor, in context: CGContext) {
	fill(path, color, in: context)
	stroke(path, in: context)
}

func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath {
	CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil)
}

/// A path from SVG path data — the subset the Apple logo uses (M, L, H, V, C, S, A, Z, absolute
/// and relative).
func svgPath(_ data: String, transform: CGAffineTransform) -> CGPath {
	var tokens: [String] = []
	var number = ""
	func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
	for character in data {
		if character.isLetter && character != "e" {
			flush(); tokens.append(String(character))
		} else if character == "-" && !number.hasSuffix("e") {
			flush(); number = "-"
		} else if character == "." && number.contains(".") {
			flush(); number = "."
		} else if character == " " || character == "," {
			flush()
		} else {
			number.append(character)
		}
	}
	flush()

	let path = CGMutablePath()
	var index = 0
	var command = Character("M")
	var current = CGPoint.zero, start = CGPoint.zero, lastControl: CGPoint?
	func next() -> CGFloat { defer { index += 1 }; return CGFloat(Double(tokens[index])!) }
	func point(_ relative: Bool) -> CGPoint {
		let x = next(), y = next()
		return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
	}
	while index < tokens.count {
		if let letter = tokens[index].first, letter.isLetter { command = letter; index += 1 }
		let relative = command.isLowercase
		switch command.uppercased() {
		case "M":
			current = point(relative); start = current
			path.move(to: current)
			command = relative ? "l" : "L"
			lastControl = nil
		case "L":
			current = point(relative); path.addLine(to: current); lastControl = nil
		case "H":
			current.x = relative ? current.x + next() : next(); path.addLine(to: current); lastControl = nil
		case "V":
			current.y = relative ? current.y + next() : next(); path.addLine(to: current); lastControl = nil
		case "C":
			let c1 = point(relative), c2 = point(relative), end = point(relative)
			path.addCurve(to: end, control1: c1, control2: c2)
			current = end; lastControl = c2
		case "S":
			let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
			let c2 = point(relative), end = point(relative)
			path.addCurve(to: end, control1: c1, control2: c2)
			current = end; lastControl = c2
		case "A":
			let rx = next(), ry = next(), rotation = next() * .pi / 180
			let largeArc = next() != 0, sweep = next() != 0
			let end = point(relative)
			addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
			current = end; lastControl = nil
		case "Z":
			path.closeSubpath(); current = start; lastControl = nil
		default:
			fatalError("Unsupported SVG command \(command)")
		}
	}
	return path.copy(using: [transform])!
}

/// SVG's endpoint arc, as cubic segments.
func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat, largeArc: Bool, sweep: Bool) {
	var rx = abs(rx), ry = abs(ry)
	let cosφ = cos(rotation), sinφ = sin(rotation)
	let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
	let x1 = cosφ * dx + sinφ * dy, y1 = -sinφ * dx + cosφ * dy
	let λ = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
	if λ > 1 { rx *= sqrt(λ); ry *= sqrt(λ) }
	let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
	let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
	let factor = (largeArc == sweep ? -1 : 1) * sqrt(max(0, numerator / denominator))
	let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
	let cx = cosφ * cx1 - sinφ * cy1 + (p0.x + p1.x) / 2
	let cy = sinφ * cx1 + cosφ * cy1 + (p0.y + p1.y) / 2
	func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
		atan2(ux * vy - uy * vx, ux * vx + uy * vy)
	}
	let θ1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
	var Δθ = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
	if !sweep && Δθ > 0 { Δθ -= 2 * .pi } else if sweep && Δθ < 0 { Δθ += 2 * .pi }
	let segments = Int(ceil(abs(Δθ) / (.pi / 2)))
	let δ = Δθ / CGFloat(segments)
	let k = 4 / 3 * tan(δ / 4)
	func onArc(_ θ: CGFloat) -> (CGPoint, CGPoint) {
		let x = rx * cos(θ), y = ry * sin(θ)
		let tx = -rx * sin(θ), ty = ry * cos(θ)
		return (
			CGPoint(x: cx + cosφ * x - sinφ * y, y: cy + sinφ * x + cosφ * y),
			CGPoint(x: cosφ * tx - sinφ * ty, y: sinφ * tx + cosφ * ty)
		)
	}
	for segment in 0..<segments {
		let θa = θ1 + CGFloat(segment) * δ, θb = θa + δ
		let (a, ta) = onArc(θa), (b, tb) = onArc(θb)
		path.addCurve(
			to: b,
			control1: CGPoint(x: a.x + k * ta.x, y: a.y + k * ta.y),
			control2: CGPoint(x: b.x - k * tb.x, y: b.y - k * tb.y)
		)
	}
}

/// Springfield's sky: a blue gradient with its flat-bottomed clouds.
func drawSky(in context: CGContext, body: CGRect) {
	let gradient = CGGradient(colorsSpace: nil, colors: [rgb(0x3E8EDE), rgb(0x8FD0F7)] as CFArray, locations: [0, 1])!
	context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: body.minY), end: CGPoint(x: 512, y: body.maxY), options: [])

	let clouds = CGMutablePath()
	for (x, y, r) in [(705.0, 238.0, 34.0), (752, 214, 50), (808, 226, 40), (848, 244, 26), (160, 330, 26), (198, 312, 38), (238, 326, 28)] {
		clouds.addPath(circle(x, y, r))
	}
	clouds.addRoundedRect(in: CGRect(x: 690, y: 230, width: 178, height: 40), cornerWidth: 20, cornerHeight: 20)
	clouds.addRoundedRect(in: CGRect(x: 140, y: 324, width: 120, height: 32), cornerWidth: 16, cornerHeight: 16)
	fill(clouds, rgb(0xF4FAFF), in: context)
}

/// Homer, three-quarters to the right, mouth wide open for the apple.
func drawHomer(in context: CGContext) {
	// Neck: thick and short, the back of it carrying on from the back of the head.
	let neck = CGMutablePath()
	neck.move(to: CGPoint(x: 318, y: 640))
	neck.addCurve(to: CGPoint(x: 296, y: 880), control1: CGPoint(x: 312, y: 730), control2: CGPoint(x: 300, y: 820))
	neck.addLine(to: CGPoint(x: 296, y: 1000))
	neck.addLine(to: CGPoint(x: 660, y: 1000))
	neck.addLine(to: CGPoint(x: 660, y: 880))
	neck.addCurve(to: CGPoint(x: 640, y: 720), control1: CGPoint(x: 652, y: 820), control2: CGPoint(x: 642, y: 760))
	fill(neck, skin, in: context)
	let neckLines = CGMutablePath()
	neckLines.move(to: CGPoint(x: 318, y: 640))
	neckLines.addCurve(to: CGPoint(x: 296, y: 880), control1: CGPoint(x: 312, y: 730), control2: CGPoint(x: 300, y: 820))
	neckLines.move(to: CGPoint(x: 630, y: 760))
	neckLines.addCurve(to: CGPoint(x: 660, y: 880), control1: CGPoint(x: 640, y: 790), control2: CGPoint(x: 652, y: 830))
	stroke(neckLines, in: context)

	// His white shirt, open at the collar.
	let shirt = CGMutablePath()
	shirt.move(to: CGPoint(x: 60, y: 990))
	shirt.addCurve(to: CGPoint(x: 300, y: 846), control1: CGPoint(x: 110, y: 900), control2: CGPoint(x: 210, y: 858))
	shirt.addLine(to: CGPoint(x: 352, y: 828))
	shirt.addLine(to: CGPoint(x: 470, y: 930))
	shirt.addLine(to: CGPoint(x: 600, y: 830))
	shirt.addLine(to: CGPoint(x: 664, y: 846))
	shirt.addCurve(to: CGPoint(x: 900, y: 990), control1: CGPoint(x: 760, y: 862), control2: CGPoint(x: 860, y: 910))
	shirt.closeSubpath()
	fillAndStroke(shirt, rgb(0xFFFFFF), in: context)
	let collar = CGMutablePath()
	collar.move(to: CGPoint(x: 352, y: 828))
	collar.addLine(to: CGPoint(x: 392, y: 900))
	collar.addLine(to: CGPoint(x: 440, y: 902))
	collar.move(to: CGPoint(x: 600, y: 830))
	collar.addLine(to: CGPoint(x: 572, y: 904))
	collar.addLine(to: CGPoint(x: 520, y: 906))
	collar.move(to: CGPoint(x: 470, y: 930))
	collar.addLine(to: CGPoint(x: 470, y: 1000))
	stroke(collar, in: context)

	// Ear, behind the back of the head, level with the nose.
	let ear = CGMutablePath()
	ear.move(to: CGPoint(x: 310, y: 452))
	ear.addCurve(to: CGPoint(x: 248, y: 520), control1: CGPoint(x: 268, y: 446), control2: CGPoint(x: 246, y: 478))
	ear.addCurve(to: CGPoint(x: 318, y: 584), control1: CGPoint(x: 250, y: 566), control2: CGPoint(x: 290, y: 590))
	ear.closeSubpath()
	fillAndStroke(ear, skin, in: context)

	// The cranium: a tall dome, the back of the head nearly straight.
	let skull = CGMutablePath()
	skull.move(to: CGPoint(x: 318, y: 660))
	skull.addCurve(to: CGPoint(x: 298, y: 360), control1: CGPoint(x: 304, y: 560), control2: CGPoint(x: 292, y: 450))
	skull.addCurve(to: CGPoint(x: 470, y: 158), control1: CGPoint(x: 304, y: 236), control2: CGPoint(x: 372, y: 158))
	skull.addCurve(to: CGPoint(x: 638, y: 318), control1: CGPoint(x: 570, y: 158), control2: CGPoint(x: 634, y: 228))
	skull.addLine(to: CGPoint(x: 642, y: 368))
	let head = skull.mutableCopy()!
	head.addLine(to: CGPoint(x: 640, y: 720))
	head.addLine(to: CGPoint(x: 318, y: 720))
	fill(head, skin, in: context)
	stroke(skull, in: context)

	// Inside of the ear.
	let innerEar = CGMutablePath()
	innerEar.move(to: CGPoint(x: 300, y: 488))
	innerEar.addCurve(to: CGPoint(x: 274, y: 522), control1: CGPoint(x: 284, y: 488), control2: CGPoint(x: 272, y: 502))
	innerEar.addCurve(to: CGPoint(x: 298, y: 540), control1: CGPoint(x: 278, y: 536), control2: CGPoint(x: 290, y: 540))
	innerEar.move(to: CGPoint(x: 280, y: 548))
	innerEar.addCurve(to: CGPoint(x: 304, y: 562), control1: CGPoint(x: 286, y: 558), control2: CGPoint(x: 296, y: 562))
	stroke(innerEar, in: context, width: 6)

	// The stubbled muzzle: from the cheek under the eye along the nose to the upper lip, the jaw
	// dropped open, round the chin and back past the jowl to the front of the ear.
	let upperLip = CGPoint(x: 724, y: 528), corner = CGPoint(x: 628, y: 580), lowerLip = CGPoint(x: 712, y: 648)
	let muzzle = CGMutablePath()
	muzzle.move(to: CGPoint(x: 470, y: 462))
	muzzle.addCurve(to: CGPoint(x: 630, y: 478), control1: CGPoint(x: 520, y: 446), control2: CGPoint(x: 590, y: 456))
	muzzle.addCurve(to: upperLip, control1: CGPoint(x: 690, y: 484), control2: CGPoint(x: 730, y: 500))
	muzzle.addCurve(to: corner, control1: CGPoint(x: 700, y: 546), control2: CGPoint(x: 656, y: 556))
	muzzle.addCurve(to: lowerLip, control1: CGPoint(x: 650, y: 616), control2: CGPoint(x: 684, y: 640))
	muzzle.addCurve(to: CGPoint(x: 650, y: 754), control1: CGPoint(x: 736, y: 680), control2: CGPoint(x: 712, y: 748))
	muzzle.addCurve(to: CGPoint(x: 452, y: 724), control1: CGPoint(x: 580, y: 762), control2: CGPoint(x: 500, y: 756))
	muzzle.addCurve(to: CGPoint(x: 384, y: 600), control1: CGPoint(x: 412, y: 698), control2: CGPoint(x: 386, y: 650))
	muzzle.addCurve(to: CGPoint(x: 470, y: 462), control1: CGPoint(x: 384, y: 534), control2: CGPoint(x: 420, y: 478))
	muzzle.closeSubpath()
	fillAndStroke(muzzle, stubble, in: context)

	// Open mouth: the dark inside and the tongue.
	let mouth = CGMutablePath()
	mouth.move(to: upperLip)
	mouth.addCurve(to: corner, control1: CGPoint(x: 700, y: 546), control2: CGPoint(x: 656, y: 556))
	mouth.addCurve(to: lowerLip, control1: CGPoint(x: 650, y: 616), control2: CGPoint(x: 684, y: 640))
	mouth.addCurve(to: upperLip, control1: CGPoint(x: 718, y: 606), control2: CGPoint(x: 722, y: 562))
	mouth.closeSubpath()
	fill(mouth, mouthInside, in: context)
	context.saveGState()
	context.addPath(mouth)
	context.clip()
	fill(CGPath(ellipseIn: CGRect(x: 650, y: 600, width: 96, height: 64), transform: nil), tongueColor, in: context)
	context.restoreGState()
	stroke(mouth, in: context)

	// Nose: the long sausage, drooping a little, over the top of the muzzle.
	let noseLine = CGMutablePath()
	noseLine.move(to: CGPoint(x: 596, y: 462))
	noseLine.addQuadCurve(to: CGPoint(x: 700, y: 482), control: CGPoint(x: 660, y: 464))
	let nose = noseLine.copy(strokingWithWidth: 60, lineCap: .round, lineJoin: .round, miterLimit: 10)
	fillAndStroke(nose, skin, in: context)

	// Eyes, the far one popping out past the forehead, both on the apple.
	for (x, y, r, pupil) in [(654.0, 376.0, 58.0, CGPoint(x: 684, y: 394)), (560, 388, 63, CGPoint(x: 596, y: 408))] {
		fillAndStroke(circle(x, y, r), rgb(0xFFFFFF), in: context)
		fill(circle(pupil.x, pupil.y, 9), ink, in: context)
	}

	// His two hairs, and the zigzag above the ear.
	let hairs = CGMutablePath()
	hairs.move(to: CGPoint(x: 424, y: 178))
	hairs.addCurve(to: CGPoint(x: 494, y: 162), control1: CGPoint(x: 416, y: 102), control2: CGPoint(x: 496, y: 98))
	hairs.move(to: CGPoint(x: 478, y: 160))
	hairs.addCurve(to: CGPoint(x: 552, y: 172), control1: CGPoint(x: 476, y: 86), control2: CGPoint(x: 558, y: 94))
	hairs.move(to: CGPoint(x: 297, y: 440))
	hairs.addLine(to: CGPoint(x: 314, y: 398))
	hairs.addLine(to: CGPoint(x: 332, y: 436))
	hairs.addLine(to: CGPoint(x: 352, y: 392))
	hairs.addLine(to: CGPoint(x: 372, y: 446))
	stroke(hairs, in: context)
}

func sausage(_ build: (CGMutablePath) -> Void, width: CGFloat) -> CGPath {
	let line = CGMutablePath()
	build(line)
	return line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Homer's hand holding the apple up to his mouth: the forearm out of a short sleeve, the back
/// of the hand on the apple's far side, three fingers and the thumb wrapped round its front.
func drawHand(in context: CGContext) {
	let forearm = sausage({
		$0.move(to: CGPoint(x: 836, y: 1000))
		$0.addQuadCurve(to: CGPoint(x: 872, y: 712), control: CGPoint(x: 880, y: 850))
	}, width: 94)
	fillAndStroke(forearm, skin, in: context)

	let sleeve = CGMutablePath()
	sleeve.move(to: CGPoint(x: 760, y: 1000))
	sleeve.addLine(to: CGPoint(x: 768, y: 890))
	sleeve.addCurve(to: CGPoint(x: 912, y: 900), control1: CGPoint(x: 820, y: 872), control2: CGPoint(x: 872, y: 878))
	sleeve.addLine(to: CGPoint(x: 924, y: 1000))
	sleeve.closeSubpath()
	fillAndStroke(sleeve, rgb(0xFFFFFF), in: context)

	let back = CGPath(ellipseIn: CGRect(x: 828, y: 590, width: 86, height: 150), transform: nil)
	fillAndStroke(back, skin, in: context)

	let fingers: [(CGPoint, CGPoint, CGPoint)] = [
		(CGPoint(x: 884, y: 704), CGPoint(x: 840, y: 690), CGPoint(x: 800, y: 702)),
		(CGPoint(x: 892, y: 666), CGPoint(x: 838, y: 648), CGPoint(x: 786, y: 664)),
		(CGPoint(x: 888, y: 628), CGPoint(x: 836, y: 608), CGPoint(x: 790, y: 626)),
	]
	for (knuckle, control, tip) in fingers {
		let finger = sausage({
			$0.move(to: knuckle)
			$0.addQuadCurve(to: tip, control: control)
		}, width: 38)
		fillAndStroke(finger, skin, in: context)
	}
	let thumb = sausage({
		$0.move(to: CGPoint(x: 878, y: 616))
		$0.addQuadCurve(to: CGPoint(x: 846, y: 560), control: CGPoint(x: 872, y: 576))
	}, width: 40)
	fillAndStroke(thumb, skin, in: context)
}

/// Apple's 1977–1998 rainbow logo — its own outline and stripes (Wikimedia's
/// Apple_Computer_Logo_rainbow.svg) — mirrored so the bite faces Homer's mouth.
func drawApple(in context: CGContext, origin: CGPoint, width: CGFloat) {
	// The SVG's 89.89 × 104.6 viewBox: its clip path drawn through `matrix(.61862 0 0 1 -28.72 -50.8)`.
	let scale = width / 89.89
	let transform = CGAffineTransform(a: 0.61862, b: 0, c: 0, d: 1, tx: -28.72, ty: -50.8)
		.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 89.89, ty: 0))
		.concatenating(CGAffineTransform(scaleX: scale, y: scale))
		.concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
	let logo = svgPath("""
		M150.97 50.8c-9.07.38-19.66 3.95-25.85 8.6-5.62 4.21-10.26 10.47-8.46 16.56 9.9.19 20.13-3.47 26.07-8.18 \
		5.55-4.4 9.77-10.63 8.24-16.99m3.35 24.48c-15.27 0-21.72 4.49-32.31 4.49-10.92 0-19.23-4.49-32.43-4.49 \
		-12.98 0-26.77 4.88-35.51 13.21l-.16.16A24.3 24.3 0 0 0 46.88 102c-.76 4.14-.56 8.66.62 13.35a46 46 0 0 0 \
		5.93 13.35 65 65 0 0 0 11.45 13.35c7 6.45 16.2 13.28 28.04 13.34 11.08.07 14.21-4.37 29.24-4.42s17.87 \
		4.47 28.94 4.4c11.35-.05 20.7-7 27.67-13.32l1.98-1.83a70 70 0 0 0 10.12-11.51l.87-1.18c-9.96-2.32-17.03 \
		-6.85-20.85-12.18-3-4.18-4-8.86-2.81-13.35 1.31-4.98 5.3-9.73 12.2-13.35a45 45 0 0 1 6.52-2.76c-8.72 \
		-6.72-20.95-10.61-32.48-10.61
		""", transform: transform)

	// A white rim keeps the blue stripe off the sky.
	stroke(logo, in: context, width: 14, color: rgb(0xFFFFFF))

	context.saveGState()
	context.addPath(logo)
	context.clip()
	// Stripe edges, in the SVG's y.
	let stripes: [(UInt32, CGFloat, CGFloat)] = [
		(0x75BD21, 37.45, 102), (0xFFC728, 88.65, 115.35), (0xFF661C, 102, 128.7),
		(0xCF0F2B, 115.35, 142.05), (0xB01CAB, 128.7, 155.38), (0x00A1DE, 142.06, 168.74),
	]
	for (color, top, bottom) in stripes {
		context.setFillColor(rgb(color))
		context.fill(CGRect(x: origin.x - 10, y: origin.y + (top - 50.8) * scale, width: width + 20, height: (bottom - top) * scale))
	}
	context.restoreGState()
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

/// Writes `<name>.appiconset` into the asset catalog: `image` at every size macOS asks for.
func writeIconSet(named name: String, image: NSImage) throws {
	let iconSet = assets.appending(path: "\(name).appiconset")
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
	print("Wrote \(iconSet.path)")
}

try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try """
{
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: assets.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
try writeIconSet(named: "AppIcon", image: master(debug: false))
try writeIconSet(named: "AppIconDebug", image: master(debug: true))

try FileManager.default.createDirectory(at: logoFile.deletingLastPathComponent(), withIntermediateDirectories: true)
try png(logo(), pixels: 512).write(to: logoFile)
print("Wrote \(logoFile.path)")
