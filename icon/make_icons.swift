// make_icons.swift — 风扇控制小工具的 App 图标，三个方案（A / B / C）
//
// 用 CoreGraphics 画，不依赖任何外部素材。所有尺寸、颜色都写成下面各方案的参数，改参数重跑即可。
// 用法（一般不用手动跑，直接跑同目录的 build.sh）：
//   make_icons render  <输出目录>   画出 icon-A/B/C-1024.png
//   make_icons preview <输出目录>   用 iconset 里 sips 缩好的小图拼 preview.png 和 qa/zoom-*.png
//
// 坐标约定：画布 1024×1024，左上角为原点，y 向下（和看图时一致）。光从正上方来。

import AppKit
import SwiftUI   // 只用它生成「连续曲率圆角」路径（RoundedRectangle .continuous）

// MARK: - 基础工具

let N = 1024
let S = CGFloat(N)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

struct Col {
    var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    init(_ hex: UInt32, _ a: CGFloat = 1) {
        r = CGFloat((hex >> 16) & 0xff) / 255
        g = CGFloat((hex >> 8) & 0xff) / 255
        b = CGFloat(hex & 0xff) / 255
        self.a = a
    }
    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    static func white(_ a: CGFloat) -> Col { Col(0xffffff, a) }
    static func black(_ a: CGFloat) -> Col { Col(0x000000, a) }
    func alpha(_ na: CGFloat) -> Col { Col(r: r, g: g, b: b, a: na) }
    func mix(_ o: Col, _ t: CGFloat) -> Col {
        Col(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t, a: a + (o.a - a) * t)
    }
    var cg: CGColor { CGColor(colorSpace: sRGB, components: [r, g, b, a])! }
}

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
func polar(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
}
/// 圆环（配合 evenOdd 填充）
func annulus(_ c: CGPoint, _ r0: CGFloat, _ r1: CGFloat) -> CGPath {
    let p = CGMutablePath(); p.addPath(circle(c, r1)); p.addPath(circle(c, r0)); return p
}

typealias Stops = [(CGFloat, Col)]

/// 同一种颜色、透明度从 a0 平滑过渡到 a1 的一组色标（smoothstep）
func easeStops(_ c: Col, _ a0: CGFloat, _ a1: CGFloat, steps: Int = 12) -> Stops {
    (0...steps).map { i in
        let t = CGFloat(i) / CGFloat(steps)
        let e = t * t * (3 - 2 * t)
        return (t, c.alpha(a0 + (a1 - a0) * e))
    }
}

extension CGContext {
    func grad(_ stops: Stops) -> CGGradient {
        CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1.cg } as CFArray, locations: stops.map { $0.0 })!
    }
    func fill(_ path: CGPath, _ c: Col, evenOdd: Bool = false) {
        addPath(path); setFillColor(c.cg); fillPath(using: evenOdd ? .evenOdd : .winding)
    }
    func fillLinear(_ path: CGPath, evenOdd: Bool = false, _ stops: Stops, from: CGPoint, to: CGPoint) {
        saveGState(); addPath(path); clip(using: evenOdd ? .evenOdd : .winding)
        drawLinearGradient(grad(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
    func fillRadial(_ path: CGPath, evenOdd: Bool = false, _ stops: Stops, center: CGPoint, r0: CGFloat = 0, r1: CGFloat) {
        saveGState(); addPath(path); clip(using: evenOdd ? .evenOdd : .winding)
        drawRadialGradient(grad(stops), startCenter: center, startRadius: r0, endCenter: center, endRadius: r1,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
    /// 外投影 / 发光。down > 0 表示影子往下偏（投影偏移不受 CTM 影响，这里统一换算）
    func withShadow(_ c: Col, blur: CGFloat, dx: CGFloat = 0, down: CGFloat = 0, _ body: () -> Void) {
        saveGState(); setShadow(offset: CGSize(width: dx, height: -down), blur: blur, color: c.cg); body(); restoreGState()
    }
    /// 内阴影 / 内高光：只在 path 内部留下一圈柔边
    func innerShadow(_ path: CGPath, evenOdd: Bool = false, _ c: Col, blur: CGFloat, dx: CGFloat = 0, down: CGFloat = 0) {
        saveGState()
        addPath(path); clip(using: evenOdd ? .evenOdd : .winding)
        setShadow(offset: CGSize(width: dx, height: -down), blur: blur, color: c.cg)
        let hole = CGMutablePath()
        hole.addRect(CGRect(x: -600, y: -600, width: S + 1200, height: S + 1200))
        hole.addPath(path)
        addPath(hole); setFillColor(Col.black(1).cg); fillPath(using: .evenOdd)
        restoreGState()
    }
    /// 沿 path 内侧描一圈宽 width 的渐变边
    func rim(_ path: CGPath, width: CGFloat, _ stops: Stops, from: CGPoint, to: CGPoint) {
        saveGState()
        addPath(path); clip()
        addPath(path.copy(strokingWithWidth: width * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)); clip()
        drawLinearGradient(grad(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }
    /// 在 y 向下的坐标系里正着画一张位图
    func drawUpright(_ img: CGImage, in r: CGRect) {
        saveGState(); translateBy(x: r.minX, y: r.maxY); scaleBy(x: 1, y: -1)
        draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height)); restoreGState()
    }
}

func makeContext16(_ w: Int = N, _ h: Int = N) -> CGContext {
    // 16 位通道：深色大面积渐变在 8 位下会出色带，先用 16 位画，导出时再抖动降到 8 位
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: w * 8, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true); ctx.setAllowsAntialiasing(true); ctx.interpolationQuality = .high
    return ctx
}

struct SplitMix64 {   // 固定种子的伪随机数，保证每次导出的抖动噪声一模一样
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// 16 位预乘 → 8 位非预乘，带 ±0.5 级随机抖动，写成 PNG
func writePNG(_ ctx: CGContext, to path: String, seed: UInt64) {
    let w = ctx.width, h = ctx.height
    let src = ctx.data!.bindMemory(to: UInt16.self, capacity: w * h * 4)
    var out = [UInt8](repeating: 0, count: w * h * 4)
    var rng = SplitMix64(s: seed)
    for i in 0..<(w * h) {
        let a16 = src[i * 4 + 3]
        if a16 == 0 { continue }
        let a = Double(a16) / 65535
        for k in 0..<3 {
            let v = min(1, Double(src[i * 4 + k]) / 65535 / a)
            out[i * 4 + k] = UInt8(max(0, min(255, (v * 255 + rng.unit()).rounded(.down))))
        }
        out[i * 4 + 3] = a16 == 65535 ? 255 : UInt8(max(0, min(255, (a * 255 + rng.unit()).rounded(.down))))
    }
    let provider = CGDataProvider(data: Data(out) as CFData)!
    let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: sRGB,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                      decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("写不出 \(path)") }
}

// MARK: - 图标外形（对照本机系统图标量出来的，见 tools/measure_system_icon.swift 和 tools/fit_shape.swift）

/// macOS 27.2 系统图标：不透明主体 824×824（x、y 都是 100...923），连续曲率圆角，
/// 用 SwiftUI 的 .continuous 圆角去套，半径 214.25（= 边长 × 0.26）时和系统图标只差 ~160 个边缘像素。
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 214.25
func bodyPath() -> CGPath { RoundedRectangle(cornerRadius: bodyRadius, style: .continuous).path(in: bodyRect).cgPath }

/// 系统图标自带的投影：黑色，往下偏 8px。这三个数是 tools/fit_shadow.swift 对着系统图标拟合出来的。
struct BodyShadow {
    var alpha: CGFloat = 0.25
    var blur: CGFloat = 32
    var down: CGFloat = 8
}

struct BodyStyle {
    var top: Col
    var bottom: Col
    var sheen: CGFloat = 0.07        // 顶部柔光强度
    var rimTop: CGFloat = 0.30       // 上缘高光
    var rimBottom: CGFloat = 0.45    // 下缘压暗
    var shadow = BodyShadow()
}

func drawBody(_ ctx: CGContext, _ st: BodyStyle) {
    let body = bodyPath()
    // 投影
    ctx.withShadow(.black(st.shadow.alpha), blur: st.shadow.blur, down: st.shadow.down) { ctx.fill(body, st.bottom) }
    // 底色：上浅下深
    ctx.fillLinear(body, [(0, st.top), (1, st.bottom)], from: pt(512, bodyRect.minY), to: pt(512, bodyRect.maxY))
    // 顶部一片柔光，让表面有点弧度感
    ctx.fillRadial(body, [(0, .white(st.sheen)), (1, .white(0))], center: pt(512, bodyRect.minY - 120), r1: 760)
    // 边缘：上缘一道细高光，下缘压暗
    ctx.rim(body, width: 3, [(0, .white(st.rimTop)), (0.35, .white(st.rimTop * 0.18)), (0.7, .white(0.02)), (1, .black(st.rimBottom))],
            from: pt(512, bodyRect.minY), to: pt(512, bodyRect.maxY))
    ctx.rim(body, width: 1.25, [(0, .white(st.rimTop * 0.9)), (0.25, .white(0)), (1, .white(0))],
            from: pt(512, bodyRect.minY), to: pt(512, bodyRect.maxY))
}

// MARK: - 扇叶

/// 一片扇叶（以转子中心为原点，根部中线朝 +x；sweep > 0 时叶片往顺时针方向弯）
struct Blade {
    var rRoot: CGFloat
    var rTip: CGFloat
    var rootWidth: CGFloat           // 根部张角（度）
    var tipWidth: CGFloat            // 叶尖张角（度）
    var sweep: CGFloat               // 中线从根到尖一共转过多少度
    var bend: CGFloat = 1.2          // 弯曲集中在外侧的程度（1 = 均匀）
    var widthEase: CGFloat = 1.0     // 张角从根到尖的过渡（<1 更早变宽）
    var round: CGFloat = 12          // 轮廓圆角半径

    func centerAngle(_ t: CGFloat) -> CGFloat { deg(sweep) * pow(t, bend) }
    func halfWidth(_ t: CGFloat) -> CGFloat { deg(rootWidth + (tipWidth - rootWidth) * pow(t, widthEase)) / 2 }

    func path() -> CGPath {
        let n = 72
        let rt = rTip - round
        var lead: [CGPoint] = [], trail: [CGPoint] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let r = rRoot + (rt - rRoot) * t
            let phi = centerAngle(t)
            let h = max(halfWidth(t) - round / r, 0.01)
            lead.append(polar(.zero, r, phi + h))
            trail.append(polar(.zero, r, phi - h))
        }
        let p = CGMutablePath()
        p.move(to: lead[0])
        for q in lead.dropFirst() { p.addLine(to: q) }
        let h1 = max(halfWidth(1) - round / rt, 0.01)
        p.addArc(center: .zero, radius: rt, startAngle: centerAngle(1) + h1, endAngle: centerAngle(1) - h1, clockwise: true)
        for q in trail.reversed() { p.addLine(to: q) }
        p.closeSubpath()
        if round <= 0 { return p }
        // 向外扩 round 并把所有尖角磨圆
        let fat = p.copy(strokingWithWidth: round * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return p.union(fat)
    }
    /// 叶片中部「横跨叶片」的一条线段（做从一侧边到另一侧边的渐变用）
    func crossLine(at t: CGFloat = 0.6) -> (CGPoint, CGPoint) {
        let r = rRoot + (rTip - rRoot) * t
        return (polar(.zero, r, centerAngle(t) - halfWidth(t)), polar(.zero, r, centerAngle(t) + halfWidth(t)))
    }
}

func bladeTransform(_ c: CGPoint, _ angle: CGFloat) -> CGAffineTransform {
    CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
}
func allBlades(_ blade: CGPath, center c: CGPoint, count: Int, offset: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<count { p.addPath(blade, transform: bladeTransform(c, offset + CGFloat(i) * 2 * .pi / CGFloat(count))) }
    return p
}

/// 叶片两条长边的明暗：凸的那条边（迎风边）一道亮线，凹的那条边一道暗线。
/// angle 是这片叶子的旋转角；内阴影的偏移不跟 CTM 走，所以这里自己换算成画布方向。
func bladeEdges(_ ctx: CGContext, _ world: CGPath, _ b: Blade, angle: CGFloat,
                light: Col, lightBlur: CGFloat, lightShift: CGFloat, dark: Col, darkBlur: CGFloat, darkShift: CGFloat) {
    let phi = angle + b.centerAngle(0.6)
    let ex = -sin(phi), ey = cos(phi)          // 沿圆周方向（角度增大的方向）
    ctx.innerShadow(world, dark, blur: darkBlur, dx: -ex * darkShift, down: -ey * darkShift)
    ctx.innerShadow(world, light, blur: lightBlur, dx: ex * lightShift, down: ey * lightShift)
}

// MARK: - 轮毂

/// 锥形光泽（车削金属那种沿圆周明暗交替的反光），按像素算，避免色带
func conicSheen(diameter: Int, axis: CGFloat, light: CGFloat, dark: CGFloat, sharp: CGFloat) -> CGImage {
    let d = diameter
    var buf = [UInt16](repeating: 0, count: d * d * 4)
    let c = CGFloat(d) / 2
    for y in 0..<d {
        for x in 0..<d {
            let dx = CGFloat(x) + 0.5 - c, dy = CGFloat(y) + 0.5 - c
            let v = cos(2 * (atan2(dy, dx) - axis))
            let m = pow(abs(v), sharp)
            let (g, a): (CGFloat, CGFloat) = v > 0 ? (1, light * m) : (0, dark * m)
            let i = (y * d + x) * 4
            let pa = UInt16(max(0, min(65535, a * 65535)))
            let pg = UInt16(max(0, min(65535, g * a * 65535)))
            buf[i] = pg; buf[i + 1] = pg; buf[i + 2] = pg; buf[i + 3] = pa
        }
    }
    let data = buf.withUnsafeBufferPointer { Data(buffer: $0) }
    return CGImage(width: d, height: d, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: d * 8, space: sRGB,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                   provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

struct HubStyle {
    var r: CGFloat
    var top: Col
    var bottom: Col
    var sheenLight: CGFloat = 0.16
    var sheenDark: CGFloat = 0.22
    var capR: CGFloat = 0.42          // 中心小盖的半径（占轮毂半径的比例），0 = 不画
    var shadowAlpha: CGFloat = 0.7
}

func drawHub(_ ctx: CGContext, _ c: CGPoint, _ st: HubStyle) {
    let r = st.r
    let disc = circle(c, r)
    ctx.withShadow(.black(st.shadowAlpha), blur: r * 0.34, down: r * 0.10) { ctx.fill(disc, st.bottom) }
    ctx.fillLinear(disc, [(0, st.top), (1, st.bottom)], from: pt(c.x, c.y - r), to: pt(c.x, c.y + r))
    // 车削反光
    ctx.saveGState(); ctx.addPath(disc); ctx.clip()
    let d = Int((r * 2).rounded(.up))
    ctx.drawUpright(conicSheen(diameter: d, axis: deg(-58), light: st.sheenLight, dark: st.sheenDark, sharp: 2.2),
                    in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ctx.restoreGState()
    // 边缘倒角：上亮下暗
    ctx.rim(disc, width: max(2, r * 0.05), [(0, .white(0.50)), (0.45, .white(0.06)), (1, .black(0.45))],
            from: pt(c.x, c.y - r), to: pt(c.x, c.y + r))
    if st.capR > 0 {
        // 中心小凹盖：明暗和外圈相反，看起来是凹下去的
        let cr = r * st.capR
        let cap = circle(c, cr)
        ctx.fillLinear(cap, [(0, st.bottom.mix(.black(1), 0.35)), (1, st.top.mix(.white(1), 0.05))],
                       from: pt(c.x, c.y - cr), to: pt(c.x, c.y + cr))
        ctx.innerShadow(cap, .black(0.6), blur: cr * 0.5, down: cr * 0.22)
        ctx.rim(cap, width: 1.5, [(0, .black(0.5)), (0.6, .white(0.05)), (1, .white(0.35))],
                from: pt(c.x, c.y - cr), to: pt(c.x, c.y + cr))
    }
}

// MARK: - 方案 A：井里的转子 + 冰蓝光环

struct ParamsA {
    var accent = Col(0x4FBEFF)          // 冰蓝
    var accentCore = Col(0xE4F6FF)      // 光环中线最亮处
    var body = BodyStyle(top: Col(0x30333A), bottom: Col(0x131417))
    var center = pt(512, 512)
    var wellR: CGFloat = 334            // 圆井半径
    var bezel: CGFloat = 14             // 井口倒角宽
    var ringR: CGFloat = 306            // 光环半径
    var ringW: CGFloat = 18             // 光环线宽
    var glow: CGFloat = 44              // 光环光晕的柔边
    var tipR: CGFloat = 276             // 叶尖半径
    var blades = 7
    var bladeOffset: CGFloat = -8       // 整个转子的起始角（度）
    var blade = Blade(rRoot: 66, rTip: 276, rootWidth: 30, tipWidth: 36, sweep: 46, bend: 1.15, widthEase: 0.8, round: 15)
    var bladeLight = Col(0xC2C9D3)      // 叶片迎光一侧
    var bladeDark = Col(0x3A3E46)       // 叶片背光一侧
    var hub = HubStyle(r: 96, top: Col(0x4A4E56), bottom: Col(0x1B1C20))
}

func drawA(_ ctx: CGContext, _ P: ParamsA) {
    drawBody(ctx, P.body)
    let c = P.center
    ctx.saveGState(); ctx.addPath(bodyPath()); ctx.clip()

    // 井口倒角：上缘背光、下缘迎光
    let outerR = P.wellR + P.bezel
    ctx.fillLinear(annulus(c, P.wellR, outerR), evenOdd: true, [(0, Col(0x0B0C0E)), (0.5, Col(0x1E2024)), (1, Col(0x565A63))],
                   from: pt(c.x, c.y - outerR), to: pt(c.x, c.y + outerR))
    // 井底
    let well = circle(c, P.wellR)
    ctx.fillRadial(well, [(0, Col(0x14161B)), (1, Col(0x060709))], center: c, r1: P.wellR)
    ctx.innerShadow(well, .black(0.9), blur: 40, down: 18)

    // 光环洒在井底上的光
    let k = { (r: CGFloat) in r / P.wellR }
    ctx.fillRadial(well, [(0, P.accent.alpha(0)), (k(P.ringR - 110), P.accent.alpha(0)), (k(P.ringR - 20), P.accent.alpha(0.18)),
                          (k(P.ringR), P.accent.alpha(0.34)), (1, P.accent.alpha(0.16))], center: c, r1: P.wellR)

    // 扇叶
    let blade = P.blade.path()
    let off = deg(P.bladeOffset)
    let (g0, g1) = P.blade.crossLine()
    for i in 0..<P.blades {
        let ang = off + CGFloat(i) * 2 * .pi / CGFloat(P.blades)
        let tf = bladeTransform(c, ang)
        let world = CGMutablePath(); world.addPath(blade, transform: tf)
        ctx.saveGState(); ctx.concatenate(tf)
        ctx.fillLinear(blade, [(0, P.bladeLight), (0.5, P.bladeLight.mix(P.bladeDark, 0.55)), (1, P.bladeDark)], from: g0, to: g1)
        ctx.restoreGState()
        bladeEdges(ctx, world, P.blade, angle: ang, light: .white(0.80), lightBlur: 4, lightShift: 4,
                   dark: .black(0.45), darkBlur: 14, darkShift: 8)
    }
    let fan = allBlades(blade, center: c, count: P.blades, offset: off)
    // 整体光照：上亮下暗
    ctx.fillLinear(fan, [(0, .white(0.10)), (0.5, .white(0)), (1, .black(0.26))], from: pt(c.x, c.y - P.tipR), to: pt(c.x, c.y + P.tipR))
    // 叶片靠近轮毂的地方压暗（轮毂的遮挡）
    ctx.fillRadial(fan, [(0, .black(0.50)), (0.40, .black(0.34)), (0.60, .black(0)), (1, .black(0))], center: c, r1: P.tipR)
    // 叶尖被光环照亮
    ctx.saveGState(); ctx.setBlendMode(.screen)
    ctx.fillRadial(fan, [(0, P.accent.alpha(0)), (0.66, P.accent.alpha(0)), (0.90, P.accent.alpha(0.26)), (1, P.accent.alpha(0.66))],
                   center: c, r1: P.tipR)
    ctx.restoreGState()

    // 光环：先铺两层光晕，再画本体
    let band = annulus(c, P.ringR - P.ringW / 2, P.ringR + P.ringW / 2)
    for _ in 0..<2 {
        ctx.withShadow(P.accent.alpha(0.85), blur: P.glow) { ctx.fill(band, P.accent, evenOdd: true) }
    }
    ctx.fillRadial(band, evenOdd: true, [(0, P.accent), (0.5, P.accentCore), (1, P.accent)],
                   center: c, r0: P.ringR - P.ringW / 2, r1: P.ringR + P.ringW / 2)

    drawHub(ctx, c, P.hub)
    ctx.restoreGState()
}

// MARK: - 方案 B：琥珀色三叶，三片亮度递进 = 三个档位

struct ParamsB {
    var body = BodyStyle(top: Col(0x302E2C), bottom: Col(0x131211))
    var center = pt(512, 512)
    var dishR: CGFloat = 356            // 背后那个浅碟的半径
    var blade = Blade(rRoot: 60, rTip: 322, rootWidth: 38, tipWidth: 78, sweep: 42, bend: 1.25, widthEase: 0.8, round: 40)
    var bladeOffset: CGFloat = -122     // 最亮那片的根部方向（度，0 = 朝右，顺时针为正）
    // 三片的颜色（根部色, 叶尖色），从最亮到最暗
    var levels: [(Col, Col)] = [
        (Col(0xFFA200), Col(0xFFD966)),
        (Col(0xDC7400), Col(0xF29E22)),
        (Col(0x8F4E0A), Col(0xB37218)),
    ]
    var glow = Col(0xFF9A1F)
    var shade = Col(0x7A3200)           // 叶片暗部用的深橙（不用纯黑，免得黄色发灰）
    var shine = Col(0xFFF4CF)           // 叶片高光用的暖白
    var hub = HubStyle(r: 92, top: Col(0x45423F), bottom: Col(0x191817), capR: 0.40)
}

func drawB(_ ctx: CGContext, _ P: ParamsB) {
    drawBody(ctx, P.body)
    let c = P.center
    ctx.saveGState(); ctx.addPath(bodyPath()); ctx.clip()

    // 浅碟：很浅的一圈凹陷，把三片叶子框住
    let dish = circle(c, P.dishR)
    ctx.fillRadial(dish, [(0, Col(0x0E0D0C, 0.55)), (0.8, Col(0x0E0D0C, 0.50)), (1, Col(0x0E0D0C, 0.62))], center: c, r1: P.dishR)
    ctx.innerShadow(dish, .black(0.75), blur: 30, down: 12)
    ctx.rim(annulus(c, P.dishR, P.dishR + 3), width: 3, [(0, .black(0.0)), (0.6, .white(0.03)), (1, .white(0.20))],
            from: pt(c.x, c.y - P.dishR), to: pt(c.x, c.y + P.dishR))
    ctx.fillLinear(annulus(c, P.dishR, P.dishR + 3), evenOdd: true, [(0, .black(0.35)), (0.55, .white(0.02)), (1, .white(0.22))],
                   from: pt(c.x, c.y - P.dishR), to: pt(c.x, c.y + P.dishR))

    let blade = P.blade.path()
    let (g0, g1) = P.blade.crossLine(at: 0.62)
    // 从最暗的画到最亮的
    for i in (0..<3).reversed() {
        let ang = deg(P.bladeOffset) + CGFloat(i) * 2 * .pi / 3
        let tf = bladeTransform(c, ang)
        let world = CGMutablePath(); world.addPath(blade, transform: tf)
        let (root, tip) = P.levels[i]
        // 投影 + 最亮那片的辉光
        ctx.withShadow(.black(0.60), blur: 30, down: 14) { ctx.fill(world, root) }
        if i == 0 { ctx.withShadow(P.glow.alpha(0.55), blur: 70) { ctx.fill(world, root) } }
        // 底色：根部深、叶尖亮
        ctx.fillRadial(world, [(0, root), (0.28, root), (1, tip)], center: c, r1: P.blade.rTip)
        // 横向明暗：一侧亮一侧暗，像一片有弧度的叶片
        ctx.saveGState(); ctx.concatenate(tf)
        ctx.fillLinear(blade, easeStops(P.shine, 0.26, 0), from: g0, to: g1)
        ctx.fillLinear(blade, easeStops(P.shade, 0, [0.24, 0.34, 0.40][i]), from: g0, to: g1)
        ctx.restoreGState()
        // 上缘高光、下缘压暗
        ctx.innerShadow(world, P.shine.alpha([0.80, 0.56, 0.40][i]), blur: 7, down: 5)
        ctx.innerShadow(world, P.shade.alpha(0.55), blur: 18, down: -10)
    }
    drawHub(ctx, c, P.hub)
    ctx.restoreGState()
}

// MARK: - 方案 C：银色风扇 + 一条从冷到热的上升曲线

struct ParamsC {
    var cool = Col(0x3FAEFF)            // 曲线低温端：冰蓝
    var mid = Col(0xFFF1D6)             // 曲线中段：暖白
    var hot = Col(0xFF9F1A)             // 曲线高温端：琥珀
    var body = BodyStyle(top: Col(0x2D3036), bottom: Col(0x121316))
    var fanCenter = pt(424, 414)
    var wellR: CGFloat = 262
    var bezel: CGFloat = 12
    var blades = 5
    var bladeOffset: CGFloat = -20
    var blade = Blade(rRoot: 48, rTip: 236, rootWidth: 40, tipWidth: 56, sweep: 46, bend: 1.15, widthEase: 0.8, round: 11)
    var bladeLight = Col(0xE9ECF0)
    var bladeDark = Col(0x7E848D)
    var hub = HubStyle(r: 74, top: Col(0x565A62), bottom: Col(0x202226))
    // 曲线：起点 → 拐点 → 终点（两段三次贝塞尔）
    var p0 = pt(196, 776), c1 = pt(330, 776), c2 = pt(472, 764)
    var pk = pt(570, 718), c3 = pt(684, 664), c4 = pt(794, 420)
    var p1 = pt(838, 262)
    var lineW: CGFloat = 34
    var nodeR: CGFloat = 29
}

func drawC(_ ctx: CGContext, _ P: ParamsC) {
    drawBody(ctx, P.body)
    ctx.saveGState(); ctx.addPath(bodyPath()); ctx.clip()

    let curve = CGMutablePath()
    curve.move(to: P.p0)
    curve.addCurve(to: P.pk, control1: P.c1, control2: P.c2)
    curve.addCurve(to: P.p1, control1: P.c3, control2: P.c4)
    let curveStops: Stops = [(0, P.cool), (0.52, P.mid), (1, P.hot)]

    // 曲线右下方洒出来的一片柔光（同样的冷→热渐变）。没有硬边：先做一条往右下偏的粗线的模糊影子当蒙版，再往里灌颜色
    let spill = CGMutablePath()
    spill.addPath(curve.copy(strokingWithWidth: 76, lineCap: .round, lineJoin: .round, miterLimit: 10),
                  transform: CGAffineTransform(translationX: 22, y: 30))
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 3000, height: 0), blur: 60, color: Col.black(1).cg)   // 本体画在画布外，只留影子
    ctx.translateBy(x: -3000, y: 0); ctx.fill(spill, .black(1))
    ctx.restoreGState()
    ctx.setBlendMode(.sourceIn)
    ctx.drawLinearGradient(ctx.grad(curveStops.map { ($0.0, $0.1.alpha(0.30)) }), start: pt(P.p0.x, 0), end: pt(P.p1.x, 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 风扇的圆井
    let c = P.fanCenter
    let outerR = P.wellR + P.bezel
    ctx.withShadow(.black(0.5), blur: 30, down: 6) { ctx.fill(circle(c, outerR), Col(0x0B0C0E)) }
    ctx.fillLinear(annulus(c, P.wellR, outerR), evenOdd: true, [(0, Col(0x0B0C0E)), (0.5, Col(0x202227)), (1, Col(0x5C6069))],
                   from: pt(c.x, c.y - outerR), to: pt(c.x, c.y + outerR))
    let well = circle(c, P.wellR)
    ctx.fillRadial(well, [(0, Col(0x15171B)), (1, Col(0x08090B))], center: c, r1: P.wellR)
    ctx.innerShadow(well, .black(0.9), blur: 34, down: 15)

    // 扇叶
    let blade = P.blade.path()
    let off = deg(P.bladeOffset)
    let (g0, g1) = P.blade.crossLine()
    for i in 0..<P.blades {
        let tf = bladeTransform(c, off + CGFloat(i) * 2 * .pi / CGFloat(P.blades))
        let world = CGMutablePath(); world.addPath(blade, transform: tf)
        ctx.withShadow(.black(0.55), blur: 16, down: 8) { ctx.fill(world, P.bladeDark) }
        ctx.saveGState(); ctx.concatenate(tf)
        ctx.fillLinear(blade, [(0, P.bladeLight), (0.5, P.bladeLight.mix(P.bladeDark, 0.45)), (1, P.bladeDark)], from: g0, to: g1)
        ctx.restoreGState()
        ctx.innerShadow(world, .white(0.75), blur: 4, down: 3)
        ctx.innerShadow(world, .black(0.30), blur: 12, down: -6)
    }
    let fan = allBlades(blade, center: c, count: P.blades, offset: off)
    ctx.fillLinear(fan, [(0, .white(0.12)), (0.5, .white(0)), (1, .black(0.28))],
                   from: pt(c.x, c.y - P.blade.rTip), to: pt(c.x, c.y + P.blade.rTip))
    ctx.fillRadial(fan, [(0, .black(0.50)), (0.42, .black(0.36)), (0.66, .black(0)), (1, .black(0))], center: c, r1: P.blade.rTip)
    drawHub(ctx, c, P.hub)

    // 曲线本体
    let stroke = curve.copy(strokingWithWidth: P.lineW, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.withShadow(.black(0.60), blur: 22, down: 10) { ctx.fill(stroke, Col(0x101114)) }
    ctx.fillLinear(stroke, curveStops, from: pt(P.p0.x, 0), to: pt(P.p1.x, 0))
    ctx.innerShadow(stroke, .white(0.55), blur: 5, down: 4)
    ctx.innerShadow(stroke, .black(0.30), blur: 9, down: -6)

    // 三个控制点
    for (p, t) in [(P.p0, CGFloat(0)), (P.pk, (P.pk.x - P.p0.x) / (P.p1.x - P.p0.x)), (P.p1, 1)] {
        let tint = t < 0.52 ? P.cool.mix(P.mid, t / 0.52) : P.mid.mix(P.hot, (t - 0.52) / 0.48)
        let outer = circle(p, P.nodeR + 9)
        ctx.withShadow(.black(0.60), blur: 16, down: 7) { ctx.fill(outer, Col(0x141518)) }
        ctx.fillLinear(outer, [(0, Col(0x2A2C31)), (1, Col(0x0E0F11))], from: pt(p.x, p.y - P.nodeR - 9), to: pt(p.x, p.y + P.nodeR + 9))
        let dot = circle(p, P.nodeR)
        ctx.fillLinear(dot, [(0, Col(0xFFFFFF)), (1, tint.mix(.white(1), 0.55))], from: pt(p.x, p.y - P.nodeR), to: pt(p.x, p.y + P.nodeR))
        ctx.innerShadow(dot, tint.alpha(0.65), blur: 10, down: -6)
    }
    ctx.restoreGState()
}

// MARK: - 对比图

func loadImage(_ path: String) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("读不到 \(path)") }
    return img
}
func write8(_ ctx: CGContext, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("写不出 \(path)") }
}
func makeContext8(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    return ctx
}
func label(_ ctx: CGContext, _ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: Col, centered: Bool = false) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a),
    ]
    let str = NSAttributedString(string: s, attributes: attr)
    let sz = str.size()
    str.draw(at: CGPoint(x: centered ? p.x - sz.width / 2 : p.x, y: p.y))
    NSGraphicsContext.restoreGraphicsState()
}

/// iconset 里各尺寸对应的文件名（都是 sips 从 1024 缩出来的）
let sizeFiles: [(Int, String)] = [(512, "icon_512x512.png"), (128, "icon_128x128.png"), (64, "icon_32x32@2x.png"),
                                  (32, "icon_32x32.png"), (16, "icon_16x16.png")]

func makePreview(dir: String) {
    let variants = ["A", "B", "C"]
    let gap = 44, pad = 56, labelW = 96, rowH = 512 + 92
    let panelW = pad + labelW + sizeFiles.map { $0.0 }.reduce(0, +) + gap * (sizeFiles.count - 1) + pad
    let W = panelW * 2, H = pad + rowH * variants.count + 8
    let ctx = makeContext8(W, H)
    ctx.interpolationQuality = .none
    let bgs = [Col(0x1E1E1E), Col(0xECECEC)]
    let fgs = [Col(0xF2F2F2), Col(0x1A1A1A)]
    let subs = [Col(0x8A8A8A), Col(0x6A6A6A)]
    for side in 0..<2 {
        let x0 = side * panelW
        ctx.setFillColor(bgs[side].cg); ctx.fill(CGRect(x: x0, y: 0, width: panelW, height: H))
        for (row, v) in variants.enumerated() {
            let top = pad + row * rowH
            label(ctx, v, at: pt(CGFloat(x0 + pad), CGFloat(top + 200)), size: 84, weight: .bold, color: fgs[side])
            var x = x0 + pad + labelW
            for (sz, file) in sizeFiles {
                let img = loadImage("\(dir)/icon-\(v).iconset/\(file)")
                precondition(img.width == sz && img.height == sz, "\(file) 尺寸不对")
                let y = top + (512 - sz) / 2          // 各尺寸垂直居中对齐，像素对像素，不再缩放
                ctx.drawUpright(img, in: CGRect(x: x, y: y, width: sz, height: sz))
                label(ctx, "\(sz)", at: pt(CGFloat(x) + CGFloat(sz) / 2, CGFloat(top + 512 + 14)), size: 22, weight: .medium,
                      color: subs[side], centered: true)
                x += sz + gap
            }
        }
    }
    write8(ctx, "\(dir)/preview.png")

    // 自查用：把 64 / 32 / 16 的小图按整数倍放大（最近邻），看小尺寸下糊不糊
    try? FileManager.default.createDirectory(atPath: "\(dir)/qa", withIntermediateDirectories: true)
    let zooms: [(Int, String, Int)] = [(64, "icon_32x32@2x.png", 4), (32, "icon_32x32.png", 8), (16, "icon_16x16.png", 16)]
    let cell = 256, zg = 28
    let zw = zg + variants.count * (cell + zg), zh = zg + zooms.count * (cell + zg)
    let z = makeContext8(zw * 2, zh)
    z.interpolationQuality = .none
    for side in 0..<2 {
        z.setFillColor(bgs[side].cg); z.fill(CGRect(x: side * zw, y: 0, width: zw, height: zh))
        for (row, (_, file, _)) in zooms.enumerated() {
            for (col, v) in variants.enumerated() {
                let img = loadImage("\(dir)/icon-\(v).iconset/\(file)")
                z.drawUpright(img, in: CGRect(x: side * zw + zg + col * (cell + zg), y: zg + row * (cell + zg), width: cell, height: cell))
            }
        }
    }
    write8(z, "\(dir)/qa/zoom-small.png")

    // 自查用：三个方案的 256 并排，深浅底各一行
    let s = 256, sg = 40
    let q = makeContext8(sg + 3 * (s + sg), 2 * (s + 2 * sg))
    q.interpolationQuality = .none
    for side in 0..<2 {
        q.setFillColor(bgs[side].cg); q.fill(CGRect(x: 0, y: side * (s + 2 * sg), width: sg + 3 * (s + sg), height: s + 2 * sg))
        for (col, v) in variants.enumerated() {
            let img = loadImage("\(dir)/icon-\(v).iconset/icon_256x256.png")
            q.drawUpright(img, in: CGRect(x: sg + col * (s + sg), y: side * (s + 2 * sg) + sg, width: s, height: s))
        }
    }
    write8(q, "\(dir)/qa/row-256.png")
}

// MARK: - 入口

let args = CommandLine.arguments
guard args.count >= 3 else { print("用法: make_icons render|preview <目录>"); exit(2) }
let outDir = args[2]
switch args[1] {
case "render":
    let only = args.count > 3 ? args[3] : "ABC"
    if only.contains("A") { let ctx = makeContext16(); drawA(ctx, ParamsA()); writePNG(ctx, to: "\(outDir)/icon-A-1024.png", seed: 0xA11CE) }
    if only.contains("B") { let ctx = makeContext16(); drawB(ctx, ParamsB()); writePNG(ctx, to: "\(outDir)/icon-B-1024.png", seed: 0xB0B) }
    if only.contains("C") { let ctx = makeContext16(); drawC(ctx, ParamsC()); writePNG(ctx, to: "\(outDir)/icon-C-1024.png", seed: 0xC0C0A) }
case "preview":
    makePreview(dir: outDir)
default:
    print("未知子命令 \(args[1])"); exit(2)
}
