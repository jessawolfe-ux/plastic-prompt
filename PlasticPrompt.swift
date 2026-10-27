// Plastic Prompt: a Claude prompt widget that looks like a 1999 iMac.
// A translucent plastic screen with an OS 9 chat window on it, and a plastic pill underneath to type in.
// Return pastes your message into the Terminal tab running Claude Code (same trick as Prompt Bar),
// and Claude's replies land in the chat window via the Prompt Bar hooks (~/Library/Application Support/PromptBar/*.json).
import Cocoa
import AVFoundation
import ServiceManagement

// MARK: - colours

struct Plastic { let name: String; let c: NSColor; let c2: NSColor }
func hex(_ s: String) -> NSColor { let v = Int(s.dropFirst(), radix: 16) ?? 0; return NSColor(red: CGFloat(v >> 16 & 255)/255, green: CGFloat(v >> 8 & 255)/255, blue: CGFloat(v & 255)/255, alpha: 1) }
let plastics: [Plastic] = [
    Plastic(name: "Bondi blue", c: hex("#1fb5c9"), c2: hex("#0b8ca6")),
    Plastic(name: "Strawberry", c: hex("#ff5fa2"), c2: hex("#e8237a")),
    Plastic(name: "Tangerine",  c: hex("#ff8a2a"), c2: hex("#ff5a00")),
    Plastic(name: "Blueberry",  c: hex("#3aa0ff"), c2: hex("#1a6ee0")),
    Plastic(name: "Graphite",   c: hex("#8c93a0"), c2: hex("#5a606c")),
    Plastic(name: "Indigo",     c: hex("#5a63d8"), c2: hex("#2f36a8")),
    Plastic(name: "Key Lime",   c: hex("#9be24a"), c2: hex("#5fbf12")),
]
var plastic = plastics[max(0, min(plastics.count - 1, UserDefaults.standard.integer(forKey: "colour")))]
func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor { a.blended(withFraction: t, of: b) ?? a }

let geneva = NSFont(name: "Geneva", size: 12) ?? NSFont(name: "Verdana", size: 12) ?? NSFont.systemFont(ofSize: 12)
let genevaSmall = NSFont(name: "Geneva", size: 10) ?? NSFont.systemFont(ofSize: 10)
let supportDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PromptBar")
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PlasticPrompt.log")
func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() } else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

// MARK: - sounds (synthesized: the real Mac and AIM ones are copyrighted)

final class Sounds {
    static let shared = Sounds()
    var on = UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true
    private var players: [AVAudioPlayer] = []
    private var clicks: [Data] = [], thocks: [Data] = []
    private lazy var chimeData = render(2.2) { t in
        [261.6, 329.6, 392.0, 523.3, 659.3].enumerated().reduce(0) { acc, p in
            let (i, f) = p; let s = t - Double(i) * 0.02; guard s > 0 else { return acc }
            return acc + 0.11 * tri(f * s) * exp(-s * 1.6)
        }
    }
    private lazy var blingData = render(0.32) { t in
        (t < 0.14 ? 0.10 * sin(2 * .pi * 880 * t) * exp(-t * 12) : 0) + (t >= 0.12 ? 0.10 * sin(2 * .pi * 1174.7 * (t - 0.12)) * exp(-(t - 0.12) * 7) : 0)
    }
    private lazy var creakData = render(0.36) { t in 0.05 * saw((140 + 280 * t / 0.36) * t) * exp(-t * 6) }
    private lazy var beepData = render(0.4) { t in
        let a = t < 0.07 ? sq(740 * t) : t >= 0.09 && t < 0.16 ? sq(740 * t) : t >= 0.18 ? sq(600 * t) * exp(-(t - 0.18) * 12) : 0
        return 0.08 * a
    }
    private var ups: [Data] = []
    private var sampled = false
    static let synthName = "Quiet (built in)"
    var setName = UserDefaults.standard.string(forKey: "keySet") ?? "Soft button"
    static var sets: [String] {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("sfx"), let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }
    private func samples(_ set: String, _ prefix: String) -> [Data] {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("sfx").appendingPathComponent(set), let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".wav") }.sorted().compactMap { try? Data(contentsOf: dir.appendingPathComponent($0)) }
    }
    private var synthClicks: [Data] = [], synthThocks: [Data] = [], synthUps: [Data] = []
    func use(_ set: String) {
        setName = set; UserDefaults.standard.set(set, forKey: "keySet")
        let k = samples(set, "key_"), d = samples(set, "deep_"), u = samples(set, "up_")
        if !k.isEmpty && !d.isEmpty { clicks = k; thocks = d; ups = u.isEmpty ? k : u; sampled = true }
        else { clicks = synthClicks; thocks = synthThocks; ups = synthUps; sampled = false }
    }
    private init() {
        for _ in 0..<8 {
            clicks.append(key(body: Double.random(in: 190...260), cut: Double.random(in: 1500...2100), dur: 0.055, noiseLvl: 0.32, bodyLvl: 0.30))
            thocks.append(key(body: Double.random(in: 120...160), cut: Double.random(in: 900...1300), dur: 0.08, noiseLvl: 0.36, bodyLvl: 0.42))
            ups.append(key(body: Double.random(in: 300...420), cut: Double.random(in: 2200...3000), dur: 0.03, noiseLvl: 0.14, bodyLvl: 0.08))
        }
        synthClicks = clicks; synthThocks = thocks; synthUps = ups
        use(setName)
    }
    // one key press: a low-passed puff of noise (the slider), a short damped body resonance (the case), a tiny transient (the contact)
    private func key(body: Double, cut: Double, dur: Double, noiseLvl: Double, bodyLvl: Double) -> Data {
        let rate = 44100.0, n = Int(rate * dur)
        var out = [Double](repeating: 0, count: n)
        var lp = 0.0, lp2 = 0.0
        let a = 1 - exp(-2 * .pi * cut / rate)
        for i in 0..<n {
            let t = Double(i) / rate
            let x = Sounds.noise()
            lp += a * (x - lp); lp2 += a * (lp - lp2)                       // two poles: rounder, no fizz
            let env = t < 0.0015 ? t / 0.0015 : exp(-(t - 0.0015) / (dur * 0.22))
            var v = noiseLvl * lp2 * env * 3
            v += bodyLvl * sin(2 * .pi * body * t) * exp(-t / (dur * 0.35)) * (t < 0.001 ? t / 0.001 : 1)
            v += 0.12 * exp(-t / 0.0006)                                     // the contact tick
            out[i] = v
        }
        return pack(out)
    }
    static func noise() -> Double { Double.random(in: -1...1) }
    private func tri(_ x: Double) -> Double { 2 * abs(2 * (x - floor(x + 0.5))) - 1 }
    private func sq(_ x: Double) -> Double { x - floor(x) < 0.5 ? 1 : -1 }
    private func saw(_ x: Double) -> Double { 2 * (x - floor(x + 0.5)) }
    private func render(_ dur: Double, _ f: (Double) -> Double) -> Data {
        let rate = 44100.0, n = Int(rate * dur)
        return pack((0..<n).map { f(Double($0) / rate) })
    }
    // 44.1 kHz mono 16-bit WAV in memory
    private func pack(_ samples: [Double]) -> Data {
        let n = samples.count
        var pcm = [Int16](repeating: 0, count: n)
        for i in 0..<n { pcm[i] = Int16(max(-1, min(1, samples[i])) * 32767) }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(n * 2))
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }
    private func play(_ d: Data, volume: Float = 1, rate: Float = 1) {
        guard on, let p = try? AVAudioPlayer(data: d) else { return }
        if rate != 1 { p.enableRate = true; p.rate = rate }
        p.volume = volume; p.play(); players.append(p)
        if players.count > 12 { players.removeFirst(players.count - 12) }
    }
    func chime() { play(chimeData) }
    func bling() { play(blingData) }
    func creak() { play(creakData) }
    func beep() { play(beepData) }
    func click(deep: Bool) { play((deep ? thocks : clicks).randomElement()!, volume: sampled ? (deep ? Float.random(in: 0.5...0.58) : Float.random(in: 0.4...0.48)) : Float.random(in: 0.5...0.65), rate: sampled ? Float.random(in: 0.94...1.06) : 1) }
    func clickUp() { play(ups.randomElement()!, volume: sampled ? 0.5 : 0.35) }
}

// MARK: - plastic

// draws the translucent coloured plastic: tint, gloss, rim and the long top highlight, over a blur of what's behind the window
final class PlasticView: NSView {
    let radius: CGFloat, streakRight: CGFloat
    let blur = NSVisualEffectView()
    let skin = PlasticSkin()
    init(frame: NSRect, radius: CGFloat, streakRight: CGFloat = 22) {
        self.radius = radius; self.streakRight = streakRight
        super.init(frame: frame)
        wantsLayer = true
        blur.frame = bounds; blur.autoresizingMask = [.width, .height]
        blur.material = .popover; blur.blendingMode = .behindWindow; blur.state = .active
        blur.appearance = NSAppearance(named: .aqua)
        blur.wantsLayer = true; blur.layer?.cornerRadius = radius; blur.layer?.masksToBounds = true
        addSubview(blur)
        skin.frame = bounds; skin.autoresizingMask = [.width, .height]; skin.radius = radius; skin.streakRight = streakRight
        addSubview(skin)
    }
    required init?(coder: NSCoder) { fatalError() }
    func recolour() { skin.needsDisplay = true }
}

final class PlasticSkin: NSView {
    var radius: CGFloat = 20, streakRight: CGFloat = 22
    override var isOpaque: Bool { false }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ r: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds, c = plastic.c, c2 = plastic.c2
        let path = NSBezierPath(roundedRect: b, xRadius: radius, yRadius: radius)
        path.addClip()
        // body tint
        c.withAlphaComponent(0.62).setFill(); b.fill()
        // vertical gloss: bright at the top, a touch darker at the bottom
        NSGradient(colorsAndLocations: (NSColor(white: 1, alpha: 0.55), 0), (NSColor(white: 1, alpha: 0.10), 0.38), (NSColor(white: 1, alpha: 0), 0.5), (NSColor(white: 0, alpha: 0.06), 1))?
            .draw(in: b, angle: -90)
        // deeper colour pooling at the bottom edge
        NSGradient(starting: c2.withAlphaComponent(0.45), ending: c2.withAlphaComponent(0))?.draw(in: NSRect(x: b.minX, y: b.minY, width: b.width, height: 22), angle: 90)
        // the double-shot rim: a wide soft tinted band, then a thin white edge
        g.saveGState()
        c2.withAlphaComponent(0.14).setStroke(); path.lineWidth = 28; path.stroke()
        c2.withAlphaComponent(0.28).setStroke(); path.lineWidth = 12; path.stroke()
        NSColor(white: 1, alpha: 0.55).setStroke(); path.lineWidth = 3; path.stroke()
        g.restoreGState()
        NSColor(white: 1, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: b.minX + radius * 0.6, y: b.maxY - 3.5, width: b.width - radius * 1.2, height: 2), xRadius: 1, yRadius: 1).fill()
        // the long highlight streak, drawn soft
        let sr = NSRect(x: b.minX + 22, y: b.maxY - 5 - 12, width: b.width - 22 - streakRight, height: 12)
        for (inset, a) in [(0, 0.18), (1.5, 0.22), (3, 0.3)] as [(CGFloat, CGFloat)] {
            let rr = sr.insetBy(dx: inset * 2, dy: inset)
            NSGradient(colorsAndLocations: (NSColor(white: 1, alpha: 0), 0), (NSColor(white: 1, alpha: a), 0.2), (NSColor(white: 1, alpha: a), 0.75), (NSColor(white: 1, alpha: 0), 1))?
                .draw(in: NSBezierPath(roundedRect: rr, xRadius: rr.height/2, yRadius: rr.height/2), angle: 0)
        }
    }
}

// the round plastic send button
final class GoButton: NSButton {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func draw(_ r: NSRect) {
        let b = bounds.insetBy(dx: 3, dy: 3), c = plastic.c, c2 = plastic.c2
        let down = isHighlighted
        let circle = NSBezierPath(ovalIn: down ? b.offsetBy(dx: 0, dy: -1) : b)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = NSColor(white: 0, alpha: 0.22); sh.shadowOffset = NSSize(width: 0, height: -2); sh.shadowBlurRadius = 4; sh.set()
        c.setFill(); circle.fill()
        NSGraphicsContext.restoreGraphicsState()
        circle.addClip()
        NSGradient(colorsAndLocations: (mix(c, .white, 0.3), 0), (c, 0.55), (c2, 1))?.draw(in: circle, angle: -90)
        NSGradient(starting: NSColor(white: 1, alpha: 0.95), ending: NSColor(white: 1, alpha: 0))?
            .draw(in: NSBezierPath(ovalIn: NSRect(x: b.midX - b.width * 0.3, y: b.maxY - b.height * 0.42, width: b.width * 0.6, height: b.height * 0.36)), relativeCenterPosition: .zero)
        NSColor(white: 1, alpha: 0.6).setStroke(); circle.lineWidth = 2; circle.stroke()
        // arrow
        let a = NSBezierPath(); a.lineWidth = 2.6; a.lineCapStyle = .round; a.lineJoinStyle = .round
        let cx = b.midX, cy = b.midY
        a.move(to: NSPoint(x: cx, y: cy + 7)); a.line(to: NSPoint(x: cx, y: cy - 7))
        a.move(to: NSPoint(x: cx - 6, y: cy - 1)); a.line(to: NSPoint(x: cx, y: cy - 7)); a.line(to: NSPoint(x: cx + 6, y: cy - 1))
        NSColor.white.setStroke(); a.stroke()
    }
}

// MARK: - the field

final class Field: NSTextField {
    override func mouseDown(with e: NSEvent) {
        if currentEditor() == nil {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(self)
        }
        super.mouseDown(with: e)
    }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let ed = currentEditor() as? NSTextView { ed.textColor = textColor; ed.insertionPointColor = textColor ?? .black; ed.font = font }
        return ok
    }
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command), let k = e.charactersIgnoringModifiers {
            let map: [String: Selector] = ["x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:"))]
            if let s = map[k], NSApp.sendAction(s, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: e)
    }
}
final class FieldBack: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ r: NSRect) {
        let b = bounds, p = NSBezierPath(roundedRect: b, xRadius: b.height/2, yRadius: b.height/2)
        NSColor(white: 1, alpha: 0.72).setFill(); p.fill()
        p.addClip()
        NSGradient(starting: NSColor(white: 0, alpha: 0.14), ending: NSColor(white: 0, alpha: 0))?.draw(in: NSRect(x: 0, y: b.maxY - 6, width: b.width, height: 6), angle: -90)
        NSColor(white: 0, alpha: 0.06).setStroke(); p.lineWidth = 2; p.stroke()
    }
}

// MARK: - the CRT

enum Who { case me, ai, sys }
struct Line: Codable { let t: Double; let who: Int; let text: String }

final class Platinum: NSView {   // the OS 9 window: title bar, log, scrollbar, status line
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }   // the title-bar boxes and icons work on the first click, even when the pill isn't focused
    let scroll = NSScrollView(), text = NSTextView(), bar = OS9Scroller(), status = StatusBar()
    var title = "Claude" { didSet { needsDisplay = true } }
    var onClose: (() -> Void)?, onFont: ((NSPoint) -> Void)?, onSound: ((NSPoint) -> Void)?
    let closeBox = NSRect(x: 7, y: 4, width: 11, height: 11), fontBox = NSRect(x: 24, y: 4, width: 11, height: 11), soundBox = NSRect(x: 41, y: 4, width: 11, height: 11)
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard p.y < 20 else { super.mouseDown(with: e); return }
        if closeBox.insetBy(dx: -3, dy: -3).contains(p) { onClose?() }
        else if fontBox.insetBy(dx: -3, dy: -3).contains(p) { onFont?(NSPoint(x: fontBox.minX, y: fontBox.maxY + 2)) }
        else if soundBox.insetBy(dx: -3, dy: -3).contains(p) { onSound?(NSPoint(x: soundBox.minX, y: soundBox.maxY + 2)) }
    }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.textContainerInset = NSSize(width: 6, height: 5); text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true; text.autoresizingMask = [.width]
        scroll.documentView = text; scroll.hasVerticalScroller = false; scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in self?.bar.needsDisplay = true }
        addSubview(scroll); addSubview(bar); addSubview(status)
        bar.scroll = scroll
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let b = bounds
        scroll.frame = NSRect(x: 1, y: 21, width: b.width - 2 - 17, height: b.height - 21 - 19)
        bar.frame = NSRect(x: b.width - 18, y: 21, width: 17, height: b.height - 21 - 19)
        status.frame = NSRect(x: 1, y: b.height - 19, width: b.width - 2, height: 18)
        text.frame.size.width = scroll.contentSize.width
    }
    override func draw(_ r: NSRect) {
        let b = bounds
        NSColor.white.setFill(); b.fill()
        // title bar: Platinum pinstripes with the title on a solid patch
        let tb = NSRect(x: 0, y: 0, width: b.width, height: 20)
        hex("#dddddd").setFill(); tb.fill()
        NSColor.white.setFill()
        var y: CGFloat = 4; while y < 16 { NSRect(x: 1, y: y, width: b.width - 2, height: 1).fill(); y += 2 }
        func box(_ x: CGFloat, _ kind: Int) {
            let q = NSRect(x: x, y: 4, width: 11, height: 11)
            hex("#dddddd").setFill(); q.fill()
            hex("#333333").setStroke(); NSBezierPath(rect: q.insetBy(dx: 0.5, dy: 0.5)).stroke()
            NSColor.white.setFill(); NSRect(x: q.minX + 1, y: q.minY + 1, width: 9, height: 1).fill(); NSRect(x: q.minX + 1, y: q.minY + 1, width: 1, height: 9).fill()
            hex("#999999").setFill(); NSRect(x: q.minX + 1, y: q.maxY - 2, width: 9, height: 1).fill(); NSRect(x: q.maxX - 2, y: q.minY + 1, width: 1, height: 9).fill()
            hex("#333333").setFill()
            if kind == 1 { NSRect(x: q.minX + 2, y: q.minY + 2, width: 6, height: 1).fill(); NSRect(x: q.minX + 2, y: q.minY + 2, width: 1, height: 6).fill() }
            if kind == 2 { NSRect(x: q.minX + 2, y: q.midY - 0.5, width: 7, height: 1).fill() }
            if kind == 3 { NSAttributedString(string: "A", attributes: [.font: NSFont.boldSystemFont(ofSize: 8), .foregroundColor: hex("#333333")]).draw(at: NSPoint(x: q.minX + 2.5, y: q.minY - 0.5)) }
            if kind == 4 { NSAttributedString(string: "♪", attributes: [.font: NSFont.boldSystemFont(ofSize: 8), .foregroundColor: hex("#333333")]).draw(at: NSPoint(x: q.minX + 2.5, y: q.minY - 0.5)) }
        }
        box(7, 0); box(24, 3); box(41, 4); box(b.width - 18 - 17, 1); box(b.width - 18, 2)
        let title = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black])
        let ts = title.size(), tx = (b.width - ts.width)/2
        hex("#dddddd").setFill(); NSRect(x: tx - 6, y: 2, width: ts.width + 12, height: 16).fill()
        title.draw(at: NSPoint(x: tx, y: 3))
        // frame lines
        NSColor.black.setFill()
        NSRect(x: 0, y: 20, width: b.width, height: 1).fill()
        NSBezierPath(rect: b.insetBy(dx: 0.5, dy: 0.5)).stroke()
        NSRect(x: b.width - 18, y: 21, width: 1, height: b.height - 21 - 19).fill()
    }
}

final class OS9Scroller: NSView {
    weak var scroll: NSScrollView?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    var thumb: NSRect {
        let b = bounds, track = NSRect(x: 0, y: 16, width: b.width, height: b.height - 32)
        guard let s = scroll, let d = s.documentView else { return .zero }
        let vis = s.contentView.bounds, total = max(d.frame.height, vis.height)
        let h = max(24, track.height * vis.height / total)
        let y = track.minY + (track.height - h) * (total > vis.height ? vis.origin.y / (total - vis.height) : 1)
        return NSRect(x: 1, y: y, width: b.width - 2, height: h)
    }
    override func draw(_ r: NSRect) {
        let b = bounds
        NSColor.white.setFill(); b.fill()
        hex("#dddddd").setFill(); var y: CGFloat = 0; while y < b.height { NSRect(x: 0, y: y, width: b.width, height: 1).fill(); y += 2 }
        func arrow(_ rect: NSRect, up: Bool) {
            hex("#dddddd").setFill(); rect.fill()
            NSColor.white.setFill(); NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill(); NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill()
            hex("#999999").setFill(); NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill(); NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()
            NSColor.black.setFill()
            let p = NSBezierPath(), cx = rect.midX, cy = rect.midY
            if up { p.move(to: NSPoint(x: cx, y: cy - 3)); p.line(to: NSPoint(x: cx + 4, y: cy + 2)); p.line(to: NSPoint(x: cx - 4, y: cy + 2)) }
            else  { p.move(to: NSPoint(x: cx, y: cy + 3)); p.line(to: NSPoint(x: cx + 4, y: cy - 2)); p.line(to: NSPoint(x: cx - 4, y: cy - 2)) }
            p.close(); p.fill()
            NSRect(x: rect.minX, y: up ? rect.maxY - 1 : rect.minY, width: rect.width, height: 1).fill()
        }
        arrow(NSRect(x: 0, y: 0, width: b.width, height: 16), up: true)
        arrow(NSRect(x: 0, y: b.height - 16, width: b.width, height: 16), up: false)
        let t = thumb; guard t.height > 0 else { return }
        NSGradient(colorsAndLocations: (hex("#7fa6e8"), 0), (hex("#4f7fd6"), 0.5), (hex("#3b69c4"), 1))?.draw(in: t, angle: 0)
        hex("#1c3f8f").setStroke(); NSBezierPath(rect: t.insetBy(dx: 0.5, dy: 0.5)).stroke()
        hex("#b7cdf3").setFill(); NSRect(x: t.minX + 1, y: t.minY + 1, width: t.width - 2, height: 1).fill()
        for i in 0..<4 { let yy = t.midY - 4 + CGFloat(i) * 2; hex("#1c3f8f").setFill(); NSRect(x: t.minX + 4, y: yy, width: t.width - 8, height: 1).fill(); hex("#dfe9fb").setFill(); NSRect(x: t.minX + 4, y: yy + 1, width: t.width - 8, height: 1).fill() }
    }
    override func mouseDown(with e: NSEvent) {
        guard let s = scroll, let d = s.documentView else { return }
        let p = convert(e.locationInWindow, from: nil)
        func scrollBy(_ dy: CGFloat) {
            var o = s.contentView.bounds.origin
            o.y = max(0, min(d.frame.height - s.contentView.bounds.height, o.y + dy))
            s.contentView.scroll(to: o); s.reflectScrolledClipView(s.contentView)
        }
        if p.y < 16 { scrollBy(-20); return }
        if p.y > bounds.height - 16 { scrollBy(20); return }
        let t = thumb
        if t.contains(p) {
            let start = p.y, startO = s.contentView.bounds.origin.y, track = bounds.height - 32 - t.height
            let total = d.frame.height - s.contentView.bounds.height
            while let ev = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), ev.type == .leftMouseDragged {
                let q = convert(ev.locationInWindow, from: nil)
                var o = s.contentView.bounds.origin
                o.y = max(0, min(total, startO + (q.y - start) / max(1, track) * total))
                s.contentView.scroll(to: o); s.reflectScrolledClipView(s.contentView); needsDisplay = true
            }
        } else { scrollBy(p.y < t.minY ? -s.contentView.bounds.height : s.contentView.bounds.height) }
    }
}

final class StatusBar: NSView {   // "Claude is online" / "Claude is typing…" with the wristwatch
    var text = "Claude is online" { didSet { needsDisplay = true } }
    var busy = false { didSet { needsDisplay = true } }
    var tick = 0
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        let b = bounds
        hex("#dddddd").setFill(); b.fill()
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: b.width, height: 1).fill()
        var x: CGFloat = 6
        if busy {
            // the watch
            NSColor.black.setFill(); NSRect(x: x + 3.5, y: 3, width: 5, height: 2).fill(); NSRect(x: x + 3.5, y: 14, width: 5, height: 2).fill()
            let face = NSBezierPath(ovalIn: NSRect(x: x + 1.5, y: 5, width: 9, height: 9))
            NSColor.white.setFill(); face.fill(); NSColor.black.setStroke(); face.lineWidth = 1; face.stroke()
            let c = NSPoint(x: x + 6, y: 9.5), a = CGFloat(tick % 8) / 8 * 2 * .pi
            let hand = NSBezierPath(); hand.move(to: c); hand.line(to: NSPoint(x: c.x + 3 * sin(a), y: c.y - 3 * cos(a))); hand.lineWidth = 1.2; hand.stroke()
            let h2 = NSBezierPath(); h2.move(to: c); h2.line(to: NSPoint(x: c.x + 2, y: c.y)); h2.lineWidth = 1.2; h2.stroke()
            x += 18
        }
        NSAttributedString(string: text + (busy ? "…" : ""), attributes: [.font: genevaSmall, .foregroundColor: hex("#333333")]).draw(at: NSPoint(x: x, y: 3))
    }
}

final class Glass: NSView {   // CRT glass over everything: reflection, vignette, scanlines
    override var isOpaque: Bool { false }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ r: NSRect) {
        guard let g = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds, path = NSBezierPath(roundedRect: b, xRadius: 16, yRadius: 16)
        path.addClip()
        let cs = CGColorSpaceCreateDeviceRGB()
        // reflection, top-left
        if let gr = CGGradient(colorsSpace: cs, colors: [NSColor(white: 1, alpha: 0.38).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1]) {
            g.saveGState(); g.translateBy(x: b.width * 0.12, y: b.maxY); g.scaleBy(x: 1, y: 0.55 * b.height / (0.7 * b.width))
            g.drawRadialGradient(gr, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.7 * b.width * 0.6, options: []); g.restoreGState()
        }
        // vignette
        if let gr = CGGradient(colorsSpace: cs, colors: [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.28).cgColor] as CFArray, locations: [0.55, 1]) {
            g.saveGState(); g.translateBy(x: b.midX, y: b.midY); g.scaleBy(x: 1, y: b.height / b.width)
            g.drawRadialGradient(gr, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: b.width * 0.72, options: [.drawsAfterEndLocation]); g.restoreGState()
        }
        // scanlines
        NSColor(white: 0, alpha: 0.10).setFill()
        var y = b.minY; while y < b.maxY { NSRect(x: b.minX, y: y, width: b.width, height: 1).fill(); y += 3 }
        // inner shadow into the bezel
        NSColor(white: 0, alpha: 0.35).setStroke(); path.lineWidth = 22
        g.saveGState(); g.setShadow(offset: .zero, blur: 22, color: NSColor(white: 0, alpha: 0.5).cgColor); path.stroke(); g.restoreGState()
    }
}

final class Boot: NSView {   // grey dotted screen, then the happy Mac
    var showMac = false { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func draw(_ r: NSRect) {
        let b = bounds
        hex("#c0c0c0").setFill(); NSBezierPath(roundedRect: b, xRadius: 16, yRadius: 16).fill()
        hex("#9a9a9a").setFill()
        var y = b.minY + 1; while y < b.maxY { var x = b.minX + 1; while x < b.maxX { NSRect(x: x, y: y, width: 1, height: 1).fill(); x += 3 }; y += 3 }
        guard showMac else { return }
        let w: CGFloat = 44, h: CGFloat = 52, ox = b.midX - w/2, oy = b.midY - h/2
        func rr(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: NSRect(x: ox + x, y: oy + h - y - hh, width: ww, height: hh), xRadius: rad, yRadius: rad) }
        let body = rr(2, 2, 40, 40, 4), scr = rr(8, 8, 28, 22, 0), base = rr(6, 42, 32, 7, 1)
        hex("#e9e6d8").setFill(); hex("#333333").setStroke()
        for p in [body, base] { p.fill(); p.lineWidth = 2; p.stroke() }
        NSColor.white.setFill(); scr.fill(); scr.lineWidth = 2; scr.stroke()
        let f = NSBezierPath(); f.lineWidth = 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x, y: oy + h - y) }
        f.move(to: pt(15, 15)); f.line(to: pt(15, 19)); f.move(to: pt(28, 15)); f.line(to: pt(28, 19))
        f.move(to: pt(21, 14)); f.line(to: pt(21, 20)); f.line(to: pt(24, 20))
        f.move(to: pt(15, 23)); f.curve(to: pt(29, 23), controlPoint1: pt(19, 27), controlPoint2: pt(25, 27))
        f.stroke()
    }
}

struct Session {
    let tty: String, pid: Int32, cwd: String, title: String
    var folder: String { (cwd as NSString).lastPathComponent.isEmpty ? "Claude" : (cwd as NSString).lastPathComponent }
    var name: String { title.isEmpty ? folder : title }   // what the tab is about (Claude keeps the Terminal title updated), else its folder
    var key: String { tty }                                // logs live per tab
}

final class Desktop: NSView {   // the OS 9 desktop: one icon per Claude tab, plus New Claude
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }   // the title-bar boxes and icons work on the first click, even when the pill isn't focused
    var sessions: [Session] = [] { didSet { needsDisplay = true } }
    var unread: Set<String> = [] { didSet { needsDisplay = true } }
    var selected = -1 { didSet { needsDisplay = true } }
    var onOpen: ((Session) -> Void)?, onNew: (() -> Void)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    let cell = NSSize(width: 108, height: 98), k: CGFloat = 1.6   // the icon is a 32-pt drawing scaled up
    let labelFont = NSFont(name: "Geneva", size: 11) ?? NSFont.systemFont(ofSize: 11)
    func rect(_ i: Int) -> NSRect {
        let cols = max(1, Int((bounds.width - 12) / cell.width))
        return NSRect(x: 12 + CGFloat(i % cols) * cell.width, y: 6 + CGFloat(i / cols) * cell.height, width: cell.width, height: cell.height)
    }
    override func draw(_ r: NSRect) {
        for i in 0...sessions.count {
            let q = rect(i), isNew = i == sessions.count, sel = i == selected
            let ox = q.midX - 16 * k, oy = q.minY + 2
            NSGraphicsContext.saveGraphicsState()
            let tf = NSAffineTransform(); tf.translateX(by: ox, yBy: oy); tf.scale(by: k); tf.concat()
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: rad, yRadius: rad) }
            if isNew {
                let f = rr(2, 8, 28, 20, 2), tab = rr(2, 4, 12, 6, 1)
                (sel ? hex("#7a7a66") : hex("#e9e6d8")).setFill(); hex("#333333").setStroke()
                for p in [tab, f] { p.fill(); p.lineWidth = 1.2; p.stroke() }
                hex("#333333").setFill(); NSRect(x: 15, y: 13, width: 2, height: 10).fill(); NSRect(x: 11, y: 17, width: 10, height: 2).fill()
            } else {
                let body = rr(4, 2, 24, 24, 3), scr = rr(8, 6, 16, 12, 0), base = rr(6, 27, 20, 4, 1)
                (sel ? hex("#7a7a66") : hex("#e9e6d8")).setFill(); hex("#333333").setStroke()
                for p in [body, base] { p.fill(); p.lineWidth = 1.2; p.stroke() }
                (sel ? hex("#9ab0d6") : NSColor.white).setFill(); scr.fill(); scr.lineWidth = 1.2; scr.stroke()
                hex("#333333").setFill(); NSRect(x: 12, y: 9, width: 1.5, height: 3).fill(); NSRect(x: 19, y: 9, width: 1.5, height: 3).fill()
                let m = NSBezierPath(); m.move(to: NSPoint(x: 12, y: 14)); m.curve(to: NSPoint(x: 20, y: 14), controlPoint1: NSPoint(x: 14, y: 16.5), controlPoint2: NSPoint(x: 18, y: 16.5)); m.lineWidth = 1; hex("#333333").setStroke(); m.stroke()
                if unread.contains(sessions[i].key) { hex("#d41a1a").setFill(); NSBezierPath(ovalIn: NSRect(x: 25, y: 0, width: 7, height: 7)).fill() }
            }
            NSGraphicsContext.restoreGraphicsState()
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
            let label = NSAttributedString(string: isNew ? "New Claude" : sessions[i].name, attributes: [.font: labelFont, .foregroundColor: sel ? NSColor.white : NSColor.black, .paragraphStyle: para])
            let maxW = cell.width - 6
            var ls = label.boundingRect(with: NSSize(width: maxW, height: 30), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]).size
            ls.width = min(ceil(ls.width) + 2, maxW); ls.height = min(ceil(ls.height), 30)
            let lr = NSRect(x: q.midX - ls.width / 2 - 3, y: oy + 33 * k, width: ls.width + 6, height: ls.height + 2)
            (sel ? NSColor.black : NSColor.white).setFill(); lr.fill()
            label.draw(with: NSRect(x: lr.minX + 3, y: lr.minY + 1, width: ls.width, height: ls.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let hit = (0...sessions.count).first { rect($0).contains(p) }
        selected = hit ?? -1
        guard let i = hit, e.clickCount == 2 else { return }
        if i == sessions.count { onNew?() } else { onOpen?(sessions[i]) }
    }
}

final class CRT: NSView {
    let desk = NSView(), win = Platinum(), glass = Glass(), boot = Boot(), desktop = Desktop()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.cornerRadius = 16; layer?.masksToBounds = true; layer?.backgroundColor = NSColor.black.cgColor
        desk.wantsLayer = true
        addSubview(desk); desk.addSubview(desktop); desk.addSubview(win); addSubview(glass); addSubview(boot)
        desktop.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        desk.frame = bounds; glass.frame = bounds; boot.frame = bounds
        win.frame = bounds.insetBy(dx: 8, dy: 8); desktop.frame = bounds.insetBy(dx: 4, dy: 4)
        if desk.layer?.sublayers == nil {
            let g = CAGradientLayer(); g.colors = [hex("#6f86b8").cgColor, hex("#5a73a8").cgColor]; g.frame = desk.bounds; g.name = "sky"
            desk.layer?.addSublayer(g)
        }
        desk.layer?.sublayers?.first?.frame = desk.bounds
    }
}

// MARK: - the app

final class Panel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { false } }

final class App: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSMenuDelegate {
    let W: CGFloat = 460, screenH: CGFloat = 230, gap: CGFloat = 12, pillH: CGFloat = 64
    var panel: Panel!
    var screen: PlasticView!, pill: PlasticView!, crt: CRT!, field: Field!, go: GoButton!
    var statusItem: NSStatusItem!
    var lines: [Line] = []
    var logs: [String: [Line]] = [:]            // one chat per project (folder name), matching the hooks' "project"
    var current: Session?                       // the Claude tab the pill talks to
    var sessions: [Session] = []
    var cwdCache: [Int32: String] = [:]
    var quiet = UserDefaults.standard.object(forKey: "quiet") as? Bool ?? true   // send without bringing Terminal forward
    var logFont = UserDefaults.standard.string(forKey: "logFont") ?? "Geneva"
    var logSize = CGFloat(UserDefaults.standard.object(forKey: "logSize") as? Double ?? 12)
    var logColour = UserDefaults.standard.string(forKey: "logColour") ?? "#000000"
    var bodyFont: NSFont { NSFont(name: logFont, size: logSize) ?? NSFont.systemFont(ofSize: logSize) }
    var smallFont: NSFont { NSFont(name: logFont, size: max(8, logSize - 2)) ?? NSFont.systemFont(ofSize: max(8, logSize - 2)) }
    var lastApp: NSRunningApplication?
    var sending = false
    var seen: [String: Double] = [:]
    var pollTick = 0
    let me: String = {
        let n = NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
        return n.lowercased()
    }()
    let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm:ss a"; return f }()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, a.bundleIdentifier != Bundle.main.bundleIdentifier { self?.lastApp = a }
        }
        lastApp = NSWorkspace.shared.frontmostApplication

        let H = screenH + gap + pillH
        let mouse = NSEvent.mouseLocation
        let scr = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!).visibleFrame
        panel = Panel(contentRect: NSRect(x: scr.maxX - W - 24, y: scr.minY + 24, width: W, height: H), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.setFrameAutosaveName("PlasticPrompt")
        let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H)); root.wantsLayer = true
        panel.contentView = root

        // screen
        screen = PlasticView(frame: NSRect(x: 0, y: pillH + gap, width: W, height: screenH), radius: 26)
        root.addSubview(screen)
        crt = CRT(frame: screen.bounds.insetBy(dx: 12, dy: 12))
        screen.addSubview(crt, positioned: .above, relativeTo: screen.skin)
        // pill
        pill = PlasticView(frame: NSRect(x: 0, y: 0, width: W, height: pillH), radius: pillH/2, streakRight: 60)
        root.addSubview(pill)
        let apple = NSImageView(frame: NSRect(x: 16, y: pillH/2 - 10, width: 20, height: 20))
        apple.image = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        apple.contentTintColor = NSColor(white: 0, alpha: 0.5)
        let back = FieldBack(frame: NSRect(x: 46, y: 12, width: W - 46 - 10 - 44 - 10, height: 40))
        field = Field(frame: NSRect(x: back.frame.minX + 14, y: back.frame.midY - 11, width: back.frame.width - 28, height: 22))
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 15); field.textColor = hex("#1a1a1a"); field.delegate = self
        field.placeholderAttributedString = NSAttributedString(string: "Message Claude…", attributes: [.foregroundColor: NSColor(white: 0, alpha: 0.38), .font: NSFont.systemFont(ofSize: 15)])
        field.cell?.sendsActionOnEndEditing = false; (field.cell as? NSTextFieldCell)?.usesSingleLineMode = true
        go = GoButton(frame: NSRect(x: W - 10 - 44, y: pillH/2 - 22, width: 44, height: 44))
        go.title = ""; go.isBordered = false; go.target = self; go.action = #selector(send)
        for v in [apple, back, field, go] as [NSView] { pill.addSubview(v) }   // in order, each on top of the last: apple, the white back, the field, the button
        let rc = NSClickGestureRecognizer(target: self, action: #selector(rightClick(_:))); rc.buttonMask = 0x2
        root.addGestureRecognizer(rc)

        // menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = macIcon(); statusItem.button?.toolTip = "Plastic Prompt"
        let m = NSMenu(); m.delegate = self; statusItem.menu = m

        // key clicks while typing in the pill
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self, self.panel.isKeyWindow, self.panel.firstResponder is NSTextView, e.keyCode != 53 else { return e }
            if e.type == .keyUp { Sounds.shared.clickUp(); return e }
            if e.isARepeat { return e }
            let ch = e.charactersIgnoringModifiers ?? ""
            Sounds.shared.click(deep: ch == " " || e.keyCode == 51 || e.keyCode == 36)
            return e
        }

        loadLines()
        crt.win.onClose = { [weak self] in self?.showDesktop() }
        crt.win.onFont = { [weak self] p in self?.fontMenu(at: p) }
        crt.win.onSound = { [weak self] p in self?.soundMenu(at: p) }
        crt.desktop.onOpen = { [weak self] s in self?.open(s) }
        crt.desktop.onNew = { [weak self] in self?.newClaude() }
        refreshSessions()
        if let key = UserDefaults.standard.string(forKey: "currentKey"), let s = sessions.first(where: { $0.key == key }) { current = s } else { current = sessions.first }
        crt.win.title = current.map { "Claude · \($0.name)" } ?? "Claude"
        if let c = current { lines = logs[c.key] ?? logs[c.folder] ?? lines; logs[c.folder] = nil }   // older logs were kept by folder
        render()
        // hooks: remember what's there now so old replies don't replay
        for f in ["working.json", "doing.json", "last.json"] { seen[f] = mtime(f) }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, self.crt.win.status.busy else { return }
            self.crt.win.status.tick += 1; self.crt.win.status.needsDisplay = true
        }

        panel.orderFrontRegardless()
        bootUp(chime: true)
    }

    func bootUp(chime: Bool) {
        let b = crt.boot; b.alphaValue = 1; b.showMac = false; b.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { b.showMac = true; if chime { Sounds.shared.chime() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            NSAnimationContext.runAnimationGroup({ c in c.duration = 0.4; b.animator().alphaValue = 0 }) { b.isHidden = true }
        }
    }

    func macIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 4.5, width: 13, height: 12), xRadius: 2, yRadius: 2); body.lineWidth = 1.5; body.stroke()
            let scr = NSBezierPath(rect: NSRect(x: 5, y: 8, width: 8, height: 6)); scr.lineWidth = 1; scr.stroke()
            NSBezierPath(rect: NSRect(x: 4, y: 1.5, width: 10, height: 2)).fill()
            return true
        }
        img.isTemplate = true; return img
    }

    // MARK: log

    func loadLines() {
        if let d = UserDefaults.standard.data(forKey: "logs"), let l = try? JSONDecoder().decode([String: [Line]].self, from: d) { logs = l }
        if let d = UserDefaults.standard.data(forKey: "lines"), let l = try? JSONDecoder().decode([Line].self, from: d) { lines = l }
        if lines.isEmpty { lines = [Line(t: Date().timeIntervalSince1970, who: 2, text: "Claude is online. Type below and press Return.")] }
    }
    func saveLogs() {
        if let c = current { logs[c.key] = lines }
        UserDefaults.standard.set(try? JSONEncoder().encode(lines), forKey: "lines")
        UserDefaults.standard.set(try? JSONEncoder().encode(logs), forKey: "logs")
    }
    func add(_ who: Who, _ text: String) {
        lines.append(Line(t: Date().timeIntervalSince1970, who: who == .me ? 0 : who == .ai ? 1 : 2, text: text))
        if lines.count > 80 { lines.removeFirst(lines.count - 80) }
        saveLogs()
        render()
    }
    // a reply for another tab: keep it in that tab's log and dot its icon
    func addElsewhere(_ project: String, _ text: String) {
        var l = logs[project] ?? [Line(t: Date().timeIntervalSince1970, who: 2, text: "Claude is online. Type below and press Return.")]
        l.append(Line(t: Date().timeIntervalSince1970, who: 1, text: text)); if l.count > 80 { l.removeFirst(l.count - 80) }
        logs[project] = l; UserDefaults.standard.set(try? JSONEncoder().encode(logs), forKey: "logs")
        crt.desktop.unread.insert(project)
    }

    // MARK: tabs (one Claude per Terminal tab)

    func refreshSessions() {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-axo", "tty=,pid=,command="]; p.standardOutput = pipe
        guard (try? p.run()) != nil else { return }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        var found: [Session] = []
        let titles = tabTitles()
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, parts[0].hasPrefix("ttys"), let pid = Int32(parts[1]) else { continue }
            let cmd = parts[2].trimmingCharacters(in: .whitespaces)
            guard (cmd == "claude" || cmd.hasPrefix("claude ") || cmd.hasSuffix("/claude") || cmd.contains("/claude ")) && !cmd.contains("bg-spare") else { continue }
            let tty = "/dev/" + parts[0]
            if found.contains(where: { $0.tty == tty }) { continue }
            found.append(Session(tty: tty, pid: pid, cwd: cwd(of: pid), title: titles[tty] ?? ""))
        }
        sessions = found.sorted { $0.tty < $1.tty }   // a stable order, so icons don't jump when titles change
        crt.desktop.sessions = sessions
        if let c = current, let again = sessions.first(where: { $0.tty == c.tty }) { current = again; crt.win.title = "Claude · \(again.name)" }
    }
    // Claude keeps each Terminal tab's title set to what the chat is about ("✳ Desktop chat tab labels"); the glyph says idle or working
    func tabTitles() -> [String: String] {
        let r = run("""
        tell application "Terminal"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (tty of t) & (ASCII character 9) & (custom title of t) & linefeed
                end repeat
            end repeat
            return out
        end tell
        """)
        var m: [String: String] = [:]
        for line in r.out.split(separator: "\n") {
            let p = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard p.count == 2 else { continue }
            var t = String(p[1]).trimmingCharacters(in: .whitespaces)
            while let f = t.first, !f.isLetter && !f.isNumber { t.removeFirst() }   // drop the ✳ / ◐ status glyph
            if let dash = t.range(of: " — ") { t = String(t[..<dash.lowerBound]) }
            m[String(p[0])] = t.trimmingCharacters(in: .whitespaces)
        }
        return m
    }
    func cwd(of pid: Int32) -> String {
        if let c = cwdCache[pid] { return c }
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof"); p.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]; p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        let dir = out.split(separator: "\n").first { $0.hasPrefix("n/") }.map { String($0.dropFirst()) } ?? ""
        cwdCache[pid] = dir; return dir
    }
    func showDesktop() {
        saveLogs(); refreshSessions()
        crt.desktop.selected = -1; crt.desktop.isHidden = false; crt.win.isHidden = true
        crt.win.status.busy = false
    }
    func open(_ s: Session) {
        saveLogs()
        current = s; UserDefaults.standard.set(s.key, forKey: "currentKey")
        lines = logs[s.key] ?? [Line(t: Date().timeIntervalSince1970, who: 2, text: "Claude is online. Type below and press Return.")]
        crt.desktop.unread.remove(s.key)
        crt.win.title = "Claude · \(s.name)"; crt.win.status.text = "Claude is online"; crt.win.status.busy = false
        crt.win.isHidden = false; crt.desktop.isHidden = true
        render()
        Sounds.shared.creak()
    }
    func newClaude() {
        let op = NSOpenPanel(); op.canChooseDirectories = true; op.canChooseFiles = false; op.prompt = "Open Claude here"; op.message = "Pick the folder for this Claude"
        op.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        NSApp.activate(ignoringOtherApps: true)
        guard op.runModal() == .OK, let url = op.url else { return }
        let path = url.path.replacingOccurrences(of: "'", with: "'\\''")
        let r = run("""
        tell application "Terminal"
            do script "cd '\(path)' && claude"
        end tell
        """)
        if let e = r.err { failed(e); return }
        crt.win.status.text = "Starting Claude in \(url.lastPathComponent)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.cwdCache = [:]; self.refreshSessions()
            if let s = self.sessions.first(where: { $0.cwd == url.path && self.logs[$0.key] == nil }) ?? self.sessions.first(where: { $0.cwd == url.path }) { self.open(s) }
        }
    }

    // MARK: the title-bar menus

    @objc func pickFont(_ it: NSMenuItem) { logFont = it.title; UserDefaults.standard.set(logFont, forKey: "logFont"); render() }
    @objc func pickSize(_ it: NSMenuItem) { logSize = CGFloat(it.tag); UserDefaults.standard.set(Double(logSize), forKey: "logSize"); render() }
    @objc func pickTextColour(_ it: NSMenuItem) { logColour = it.representedObject as? String ?? "#000000"; UserDefaults.standard.set(logColour, forKey: "logColour"); render() }
    @objc func pickKeySet(_ it: NSMenuItem) { Sounds.shared.use(it.title); Sounds.shared.click(deep: false); DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { Sounds.shared.click(deep: true) } }
    func fontMenu(at p: NSPoint) {
        let m = NSMenu()
        for f in ["Geneva", "Monaco", "Palatino", "Helvetica", "Chicago", "Charcoal"] where NSFont(name: f, size: 12) != nil {
            let it = NSMenuItem(title: f, action: #selector(pickFont(_:)), keyEquivalent: ""); it.target = self; it.state = f == logFont ? .on : .off
            it.attributedTitle = NSAttributedString(string: f, attributes: [.font: NSFont(name: f, size: 13)!]); m.addItem(it)
        }
        m.addItem(.separator())
        for sz in [10, 12, 14, 16] { let it = NSMenuItem(title: "\(sz) point", action: #selector(pickSize(_:)), keyEquivalent: ""); it.tag = sz; it.target = self; it.state = CGFloat(sz) == logSize ? .on : .off; m.addItem(it) }
        m.addItem(.separator())
        for (n, c) in [("Black", "#000000"), ("Blue", "#1a2fd6"), ("Red", "#d41a1a"), ("Green", "#1b7a2e"), ("Purple", "#6a1bb0"), ("Brown", "#7a4a1b"), ("Grey", "#555555")] {
            let it = NSMenuItem(title: n, action: #selector(pickTextColour(_:)), keyEquivalent: ""); it.target = self; it.representedObject = c; it.state = c == logColour ? .on : .off
            it.attributedTitle = NSAttributedString(string: "■ " + n, attributes: [.foregroundColor: hex(c)]); m.addItem(it)
        }
        m.popUp(positioning: nil, at: p, in: crt.win)
    }
    func soundMenu(at p: NSPoint) {
        let m = NSMenu()
        for n in Sounds.sets + [Sounds.synthName] { let it = NSMenuItem(title: n, action: #selector(pickKeySet(_:)), keyEquivalent: ""); it.target = self; it.state = n == Sounds.shared.setName ? .on : .off; m.addItem(it) }
        m.addItem(.separator())
        let s = NSMenuItem(title: "Sounds on", action: #selector(toggleSounds), keyEquivalent: ""); s.target = self; s.state = Sounds.shared.on ? .on : .off; m.addItem(s)
        m.popUp(positioning: nil, at: p, in: crt.win)
    }
    func render() {
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle(); para.paragraphSpacing = 3; para.lineSpacing = 1
        for l in lines {
            let stamp = NSAttributedString(string: "(\(fmt.string(from: Date(timeIntervalSince1970: l.t)))) ", attributes: [.font: smallFont, .foregroundColor: hex("#777777"), .paragraphStyle: para])
            out.append(stamp)
            if l.who == 2 {
                out.append(NSAttributedString(string: l.text + "\n", attributes: [.font: bodyFont, .foregroundColor: hex("#666666"), .obliqueness: 0.15, .paragraphStyle: para]))
                continue
            }
            let name = l.who == 0 ? me : "Claude", col = l.who == 0 ? hex("#d41a1a") : hex("#1a2fd6")
            out.append(NSAttributedString(string: name + ": ", attributes: [.font: NSFont.boldSystemFont(ofSize: logSize), .foregroundColor: col, .paragraphStyle: para]))
            out.append(NSAttributedString(string: l.text + "\n", attributes: [.font: bodyFont, .foregroundColor: hex(logColour), .paragraphStyle: para]))
        }
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        let tv = crt.win.text
        tv.textContainerInset = NSSize(width: 6, height: 5)
        tv.textStorage?.setAttributedString(out)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let used = tv.layoutManager?.usedRect(for: tv.textContainer!).height ?? 0
        let room = crt.win.scroll.contentSize.height
        if used + 10 < room { tv.textContainerInset = NSSize(width: 6, height: (room - used) / 2) }   // a short chat sits in the middle
        DispatchQueue.main.async { tv.scrollToEndOfDocument(nil); self.crt.win.bar.needsDisplay = true }
    }

    // MARK: hooks from Claude Code

    func mtime(_ f: String) -> Double {
        (try? FileManager.default.attributesOfItem(atPath: supportDir.appendingPathComponent(f).path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }
    func json(_ f: String) -> [String: Any]? {
        guard let d = try? Data(contentsOf: supportDir.appendingPathComponent(f)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    func poll() {
        let st = crt.win.status
        func mine(_ j: [String: Any]?) -> Bool { guard let p = j?["project"] as? String, let c = current, sessions.count > 1 else { return true }; return p == c.folder || !sessions.contains { $0.folder == p } }
        let w = mtime("working.json")
        if w > (seen["working.json"] ?? 0) { seen["working.json"] = w; if mine(json("working.json")) { st.busy = true; st.text = "Claude is typing" } }
        let d = mtime("doing.json")
        if d > (seen["doing.json"] ?? 0), let j = json("doing.json"), let t = j["text"] as? String { seen["doing.json"] = d; if mine(j) { st.busy = true; st.text = t } }
        let l = mtime("last.json")
        if l > (seen["last.json"] ?? 0), let j = json("last.json") {
            seen["last.json"] = l
            let text = (j["full"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (j["text"] as? String) ?? ""
            if !text.isEmpty {
                if mine(j) { add(.ai, text.replacingOccurrences(of: "\n", with: "  ")); Sounds.shared.bling(); st.busy = false; st.text = "Claude is online" }
                else if let p = j["project"] as? String, let s = sessions.first(where: { $0.folder == p }) { addElsewhere(s.key, text.replacingOccurrences(of: "\n", with: "  ")); Sounds.shared.bling() }
            } else if mine(j) { st.busy = false; st.text = "Claude is online" }
        }
        pollTick += 1; if pollTick % 10 == 0 { refreshSessions() }   // every 5 s: new tabs appear, closed ones go
        if st.busy && Date().timeIntervalSince1970 - max(w, d) > 600 { st.busy = false; st.text = "Claude is online" }   // a turn that never reported back
    }

    // MARK: sending

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { send(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { field.stringValue = ""; panel.resignKey(); lastApp?.activate(); return true }
        return false
    }
    @objc func send() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let st = crt.win.status
        guard !text.isEmpty else { Sounds.shared.beep(); st.text = "Type something first"; DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if !st.busy { st.text = "Claude is online" } }; return }
        guard !sending else { return }
        sending = true
        let front = run("""
        if application "Terminal" is not running then return ""
        tell application "Terminal"
            if (count of windows) = 0 then return ""
            return tty of selected tab of front window
        end tell
        """)
        if let e = front.err { failed(e); return }
        let live = claudeTTYs()
        if let c = current, live.contains(c.tty) { if c.tty != front.out, let e = focusTTY(c.tty) { failed(e); return }; paste(text); return }
        if live.contains(front.out) { paste(text); return }
        if let tty = live.first { if let e = focusTTY(tty) { failed(e); return }; paste(text); return }
        // no Claude running: open Terminal with one, then paste
        st.text = "Starting Claude"
        let r = run("""
        tell application "Terminal"
            activate
            do script "claude --continue"
        end tell
        """)
        if let e = r.err { failed(e); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.paste(text) }
    }
    func paste(_ text: String) {
        let back = lastApp, pb = NSPasteboard.general, saved = pb.string(forType: .string)
        pb.clearContents(); pb.setString(text, forType: .string)
        let mine = pb.changeCount
        var r: (out: String, err: NSDictionary?) = ("", nil)
        if quiet, let term = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
            // key events posted straight to Terminal's process: it never comes forward
            func tap(_ key: CGKeyCode, cmd: Bool) {
                let src = CGEventSource(stateID: .combinedSessionState)
                guard let d = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true), let u = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }
                if cmd { d.flags = .maskCommand; u.flags = .maskCommand }
                d.postToPid(term.processIdentifier); u.postToPid(term.processIdentifier)
            }
            // let go of the keyboard while the keys are posted (the delivery only worked with the pill not key), then take the cursor back
            panel.resignKey()
            log("quiet send to Terminal pid \(term.processIdentifier), trusted \(AXIsProcessTrusted())")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { tap(9, cmd: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { tap(36, cmd: false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in guard let self else { return }; self.panel.makeKeyAndOrderFront(nil); self.panel.makeFirstResponder(self.field) }
            if !AXIsProcessTrusted() { r.err = [NSAppleScript.errorNumber: 1002, NSAppleScript.errorMessage: "Accessibility is off"] }
        } else {
            r = run("""
            tell application "Terminal" to activate
            delay 0.25
            tell application "System Events"
                keystroke "v" using command down
                delay 0.25
                key code 36
            end tell
            """)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if let b = back, b.bundleIdentifier != "com.apple.Terminal" { b.activate() } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if pb.changeCount == mine { pb.clearContents(); if let s = saved { pb.setString(s, forType: .string) } } }
        sending = false
        if let e = r.err { failed(e); return }
        field.stringValue = ""
        Sounds.shared.creak()
        add(.me, text)
        crt.win.status.busy = true; crt.win.status.text = "Claude is typing"
        if !quiet { panel.resignKey() }
    }
    func failed(_ e: NSDictionary) {
        sending = false
        let code = e[NSAppleScript.errorNumber] as? Int ?? 0
        log("\(code) \(e[NSAppleScript.errorMessage] ?? "")")
        Sounds.shared.beep()
        crt.win.status.busy = false
        if code == -1719 || code == 1002 || code == -25211 { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) }   // puts Plastic Prompt in the Accessibility list and asks
        crt.win.status.text = code == -1743 ? "Allow Automation in System Settings" : (code == -1719 || code == 1002 || code == -25211) ? "Allow Accessibility in System Settings" : "Error \(code), see ~/Library/Logs/PlasticPrompt.log"
    }
    func run(_ source: String) -> (out: String, err: NSDictionary?) {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return (r?.stringValue ?? "", err)
    }
    func claudeTTYs() -> Set<String> {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-axo", "tty=,command="]; p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        var ttys = Set<String>()
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0].hasPrefix("ttys") else { continue }
            let cmd = parts[1].trimmingCharacters(in: .whitespaces)
            if (cmd == "claude" || cmd.hasPrefix("claude ") || cmd.hasSuffix("/claude") || cmd.contains("/claude ")) && !cmd.contains("bg-spare") { ttys.insert("/dev/" + parts[0]) }
        }
        return ttys
    }
    func focusTTY(_ tty: String) -> NSDictionary? {
        run("""
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                    end if
                end repeat
            end repeat
        end tell
        """).err
    }

    // MARK: menu

    @objc func rightClick(_ g: NSClickGestureRecognizer) {
        let m = NSMenu(); menuNeedsUpdate(m)
        m.popUp(positioning: nil, at: g.location(in: panel.contentView), in: panel.contentView)
    }
    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let col = NSMenu()
        for (i, p) in plastics.enumerated() {
            let it = NSMenuItem(title: p.name, action: #selector(pickColour(_:)), keyEquivalent: ""); it.tag = i; it.target = self
            it.state = p.name == plastic.name ? .on : .off; col.addItem(it)
        }
        let ci = NSMenuItem(title: "Colour", action: nil, keyEquivalent: ""); ci.submenu = col; m.addItem(ci)
        let s = NSMenuItem(title: "Sounds", action: #selector(toggleSounds), keyEquivalent: ""); s.target = self; s.state = Sounds.shared.on ? .on : .off; m.addItem(s)
        let q = NSMenuItem(title: "Bring Terminal forward when sending", action: #selector(toggleQuiet), keyEquivalent: ""); q.target = self; q.state = quiet ? .off : .on; m.addItem(q)
        m.addItem(withTitle: "Replay boot", action: #selector(replayBoot), keyEquivalent: "").target = self
        m.addItem(withTitle: "Clear chat", action: #selector(clearChat), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: panel.isVisible ? "Hide" : "Show", action: #selector(toggleShow), keyEquivalent: "").target = self
        let li = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: ""); li.target = self
        li.state = SMAppService.mainApp.status == .enabled ? .on : .off; m.addItem(li)
        m.addItem(.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
    @objc func pickColour(_ it: NSMenuItem) {
        plastic = plastics[it.tag]; UserDefaults.standard.set(it.tag, forKey: "colour")
        screen.recolour(); pill.recolour(); go.needsDisplay = true
    }
    @objc func toggleSounds() { Sounds.shared.on.toggle(); UserDefaults.standard.set(Sounds.shared.on, forKey: "sounds") }
    @objc func toggleQuiet() { quiet.toggle(); UserDefaults.standard.set(quiet, forKey: "quiet") }
    @objc func replayBoot() { bootUp(chime: true) }
    @objc func clearChat() { lines = []; loadLines(); UserDefaults.standard.removeObject(forKey: "lines"); render() }
    @objc func toggleShow() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    @objc func toggleLogin() {
        do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } } catch { log("login item: \(error)") }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
