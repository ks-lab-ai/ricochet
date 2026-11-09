// Dessine l'icône de Ricochet : une étoile en verre liquide lancée à pleine vitesse, orange et bronze.
// Usage : xcrun swiftc -O App/make-icon.swift -o /tmp/make-icon && /tmp/make-icon App/AppIcon.iconset
//         iconutil -c icns App/AppIcon.iconset -o App/AppIcon.icns
import Cocoa

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}
func polygon(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    p.closeSubpath()
    return p
}

/// Carré à coins continus, comme les icônes macOS.
func squircle(center: CGFloat, radius a: CGFloat, power n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = center + a * copysign(pow(abs(c), 2 / n), c)
        let y = center + a * copysign(pow(abs(s), 2 / n), s)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

func fill(_ c: CGContext, _ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    c.saveGState()
    c.addPath(path)
    c.clip()
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func stroke(_ c: CGContext, _ path: CGPath, width: CGFloat, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    c.saveGState()
    c.addPath(path)
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.replacePathWithStrokedPath()
    c.clip()
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func glow(_ c: CGContext, at p: CGPoint, radius: CGFloat, _ col: CGColor) {
    let clear = col.copy(alpha: 0)!
    c.drawRadialGradient(gradient([(0, col), (1, clear)]), startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}

/// Étoile rayonnante : rayons effilés de longueurs variées, partant du centre.
func star(center: CGPoint, scale k: CGFloat = 1) -> CGPath {
    let lengths: [CGFloat] = [1.0, 0.82, 0.96, 0.78, 1.0, 0.86, 0.94, 0.8, 0.98, 0.84, 0.92]
    let p = CGMutablePath()
    for (i, len) in lengths.enumerated() {
        let angle = CGFloat(i) / CGFloat(lengths.count) * 2 * .pi + 0.14
        let r = 250 * len * k
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let side = CGPoint(x: -dir.y, y: dir.x)
        let base = 27 * k, tip = 12 * k
        func at(_ d: CGFloat, _ w: CGFloat) -> CGPoint {
            CGPoint(x: center.x + dir.x * d + side.x * w, y: center.y + dir.y * d + side.y * w)
        }
        p.move(to: at(0, -base))
        p.addLine(to: at(r - tip, -tip))
        p.addArc(center: at(r - tip, 0), radius: tip, startAngle: angle - .pi / 2, endAngle: angle + .pi / 2, clockwise: false)
        p.addLine(to: at(0, base))
        p.closeSubpath()
    }
    return p
}

func draw(_ c: CGContext) {
    let body = squircle(center: 512, radius: 412)

    // Ombre portée de l'icône
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0.2, 0.07, 0, 0.45))
    c.addPath(body)
    c.setFillColor(color(0.7, 0.32, 0.08))
    c.fillPath()
    c.restoreGState()

    // Fond : orange lumineux en haut, bronze profond en bas
    c.saveGState()
    c.addPath(body)
    c.clip()
    c.drawLinearGradient(gradient([
        (0, color(1.0, 0.68, 0.34)),
        (0.46, color(0.86, 0.40, 0.13)),
        (1, color(0.36, 0.14, 0.05)),
    ]), start: CGPoint(x: 300, y: 930), end: CGPoint(x: 720, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    glow(c, at: CGPoint(x: 270, y: 870), radius: 520, color(1, 0.95, 0.82, 0.48))
    glow(c, at: CGPoint(x: 820, y: 170), radius: 420, color(1, 0.62, 0.22, 0.42))
    glow(c, at: CGPoint(x: 170, y: 170), radius: 360, color(0.62, 0.2, 0.1, 0.5))

    // Grande courbe de verre qui traverse le fond
    let band = CGMutablePath()
    band.move(to: CGPoint(x: -60, y: 620))
    band.addCurve(to: CGPoint(x: 1090, y: 340), control1: CGPoint(x: 340, y: 300), control2: CGPoint(x: 660, y: 740))
    band.addLine(to: CGPoint(x: 1090, y: 1090))
    band.addLine(to: CGPoint(x: -60, y: 1090))
    band.closeSubpath()
    c.addPath(band)
    c.setFillColor(color(1, 1, 1, 0.07))
    c.fillPath()

    // Effet de vitesse : filets lumineux derrière l'étoile
    let center = CGPoint(x: 590, y: 512)
    for (y, x0, x1, w, a) in [
        (CGFloat(690), CGFloat(150), CGFloat(430), CGFloat(15), CGFloat(0.55)),
        (604, 120, 350, 20, 0.8),
        (512, 92, 320, 26, 1.0),
        (420, 130, 352, 20, 0.8),
        (334, 170, 440, 15, 0.55),
    ] {
        let line = CGMutablePath()
        line.move(to: CGPoint(x: x0, y: y))
        line.addLine(to: CGPoint(x: x1, y: y))
        stroke(c, line, width: w, gradient([
            (0, color(1, 0.95, 0.85, 0)),
            (1, color(1, 0.95, 0.85, 0.85 * a)),
        ]), from: CGPoint(x: x0, y: y), to: CGPoint(x: x1, y: y))
    }

    // Traînée : deux échos de l'étoile qui s'effacent vers l'arrière
    for (dx, a) in [(CGFloat(-104), CGFloat(0.13)), (-54, 0.26)] {
        c.addPath(star(center: CGPoint(x: center.x + dx, y: center.y)))
        c.setFillColor(color(1, 0.93, 0.8, a))
        c.fillPath()
    }
    c.restoreGState()

    // Étoile en verre
    let shape = star(center: center)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -26), blur: 46, color: color(0.25, 0.08, 0, 0.62))
    c.addPath(shape)
    c.setFillColor(color(1, 0.96, 0.9, 0.95))
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(shape)
    c.clip()
    c.drawLinearGradient(gradient([
        (0, color(1, 1, 1, 1)),
        (0.55, color(1, 0.93, 0.82, 1)),
        (1, color(1, 0.76, 0.5, 1)),
    ]), start: CGPoint(x: center.x - 180, y: center.y + 250), end: CGPoint(x: center.x + 180, y: center.y - 250), options: [])
    glow(c, at: center, radius: 90, color(1, 1, 1, 0.75))
    c.restoreGState()

    // Liseré du verre : lumière en haut, reflet cuivré en bas
    stroke(c, body, width: 9, gradient([
        (0, color(1, 0.98, 0.92, 0.92)),
        (0.45, color(1, 1, 1, 0.14)),
        (0.72, color(1, 0.75, 0.45, 0.14)),
        (1, color(1, 0.78, 0.48, 0.72)),
    ]), from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = points * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
