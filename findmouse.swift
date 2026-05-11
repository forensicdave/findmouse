import Cocoa
import QuartzCore

// MARK: - Config

enum Mode: String {
    case rings, border, crosshairs
}

struct Config {
    var modes:           Set<Mode>      = [.rings]
    var ringCount        = 4
    var ringMaxRadius:   CGFloat        = 120
    var ringStartRadius: CGFloat        = 8
    var lineWidth:       CGFloat        = 5
    var color                           = NSColor.systemRed
    var animationDur:    CFTimeInterval = 0.9
    var ringStagger:     CFTimeInterval = 0.12
    var debug                           = false
    var detach                          = false
}

// MARK: - Color parsing

func parseColor(_ s: String) -> NSColor? {
    let named: [String: NSColor] = [
        "red": .systemRed, "green": .systemGreen, "blue": .systemBlue,
        "yellow": .systemYellow, "orange": .systemOrange, "purple": .systemPurple,
        "pink": .systemPink, "teal": .systemTeal, "white": .white, "black": .black,
        "cyan": .cyan, "magenta": .magenta, "gray": .gray, "grey": .gray,
    ]
    if let c = named[s.lowercased()] { return c }

    var hex = s.lowercased()
    if hex.hasPrefix("#")  { hex.removeFirst() }
    if hex.hasPrefix("0x") { hex.removeFirst(2) }
    guard (hex.count == 6 || hex.count == 8), let v = UInt32(hex, radix: 16) else { return nil }
    let hasAlpha = hex.count == 8
    let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
    let g = CGFloat((v >> (hasAlpha ? 16 :  8)) & 0xFF) / 255.0
    let b = CGFloat((v >> (hasAlpha ?  8 :  0)) & 0xFF) / 255.0
    let a = hasAlpha ? CGFloat(v & 0xFF) / 255.0 : 1.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// MARK: - Usage

func printUsage() {
    print("""
    findmouse — pulse rings at the current mouse cursor

    USAGE:
      findmouse [options]

    OPTIONS:
      --mode LIST          Comma-separated list of effects to draw on the
                           cursor's screen. Any combination of:
                             rings       concentric pulse around the cursor
                             border      flashing rectangle around the screen
                             crosshairs  full-width/height lines through cursor
                           (default: rings)
      --rings N            Number of rings (default: 4)
      --max-radius N       Maximum ring radius in points (default: 120)
      --start-radius N     Starting ring radius in points (default: 8)
      --line-width N       Stroke width in points (default: 5)
      --color NAME|HEX     red, green, blue, yellow, orange, purple, pink,
                           teal, white, black, cyan, magenta, gray, or hex
                           like #FF8800 / FF8800AA (default: red)
      --duration SECS      Animation duration per ring (default: 0.9)
      --stagger SECS       Delay between successive rings (default: 0.12)
      --detach             Fork into background and return immediately (the
                           animation continues). Ignored when --debug is set.
      --debug              Print diagnostic info to stderr
      -h, --help           Show this help
    """)
}

// MARK: - Argument parsing

func die(_ msg: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(code)
}

var cfg = Config()
let args = Array(CommandLine.arguments.dropFirst())
var argIndex = 0

func takeValue(for flag: String) -> String {
    guard argIndex + 1 < args.count else { die("\(flag) requires a value") }
    argIndex += 1
    return args[argIndex]
}

func asDouble(_ flag: String, _ s: String) -> Double {
    guard let v = Double(s) else { die("\(flag) expects a number, got '\(s)'") }
    return v
}

func asInt(_ flag: String, _ s: String) -> Int {
    guard let v = Int(s) else { die("\(flag) expects an integer, got '\(s)'") }
    return v
}

while argIndex < args.count {
    let a = args[argIndex]
    switch a {
    case "-h", "--help":
        printUsage(); exit(0)
    case "--mode":
        let raw = takeValue(for: a)
        let parts = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        var newModes = Set<Mode>()
        for p in parts where !p.isEmpty {
            guard let m = Mode(rawValue: p) else { die("unknown mode '\(p)'") }
            newModes.insert(m)
        }
        if newModes.isEmpty { die("--mode requires at least one value") }
        cfg.modes = newModes
    case "--rings":
        cfg.ringCount = asInt(a, takeValue(for: a))
    case "--max-radius":
        cfg.ringMaxRadius = CGFloat(asDouble(a, takeValue(for: a)))
    case "--start-radius":
        cfg.ringStartRadius = CGFloat(asDouble(a, takeValue(for: a)))
    case "--line-width":
        cfg.lineWidth = CGFloat(asDouble(a, takeValue(for: a)))
    case "--color":
        let s = takeValue(for: a)
        guard let c = parseColor(s) else { die("unknown color '\(s)'") }
        cfg.color = c
    case "--duration":
        cfg.animationDur = asDouble(a, takeValue(for: a))
    case "--stagger":
        cfg.ringStagger = asDouble(a, takeValue(for: a))
    case "--detach":
        cfg.detach = true
    case "--debug":
        cfg.debug = true
    default:
        die("unknown option '\(a)' (use --help)")
    }
    argIndex += 1
}

// MARK: - Debug logging

func dlog(_ msg: @autoclosure () -> String) {
    guard cfg.debug else { return }
    FileHandle.standardError.write(Data("[findmouse] \(msg())\n".utf8))
}

// MARK: - Detach
// Re-spawn ourselves without --detach and exit immediately so the shell returns
// while the child finishes the animation. (fork() is unavailable in Swift's
// Foundation overlay, and forking after AppKit init is unsafe anyway.)
if cfg.detach && !cfg.debug {
    guard let exePath = Bundle.main.executablePath else {
        die("could not determine own executable path")
    }
    var childArgs = Array(CommandLine.arguments.dropFirst())
    childArgs.removeAll { $0 == "--detach" }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: exePath)
    task.arguments = childArgs
    do { try task.run() } catch { die("spawn failed: \(error)") }
    exit(0)
}

// MARK: - App

let ringsTail = cfg.modes.contains(.rings) ? Double(cfg.ringCount) * cfg.ringStagger : 0
let totalDuration = cfg.animationDur + ringsTail + 0.2

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let mouse = NSEvent.mouseLocation
dlog("mouse global: \(mouse)")
dlog("screens (\(NSScreen.screens.count)):")
for (idx, s) in NSScreen.screens.enumerated() {
    let isMain = (s == NSScreen.main) ? " [main]" : ""
    dlog("  [\(idx)] frame=\(s.frame) visibleFrame=\(s.visibleFrame) scale=\(s.backingScaleFactor)\(isMain)")
}

guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        ?? NSScreen.main else {
    die("no screen contains the cursor", code: 1)
}
dlog("selected screen frame=\(screen.frame)")

let window = NSWindow(
    contentRect: screen.frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false,
    screen: screen
)
window.isOpaque           = false
window.backgroundColor    = .clear
window.hasShadow          = false
window.level              = .screenSaver
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

// Force the window onto the chosen screen — `contentRect:` alone is unreliable on
// external displays; without this the overlay sometimes lands on the primary screen.
window.setFrame(screen.frame, display: true)
dlog("window frame after setFrame: \(window.frame)")

let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
content.wantsLayer = true
window.contentView = content

let local = CGPoint(
    x: mouse.x - screen.frame.origin.x,
    y: mouse.y - screen.frame.origin.y
)
dlog("local cursor in window: \(local)")

let now = CACurrentMediaTime()

func fadeAnimation(peak: Float = 0.9, duration: CFTimeInterval) -> CAKeyframeAnimation {
    let fade = CAKeyframeAnimation(keyPath: "opacity")
    fade.values    = [0.0, NSNumber(value: peak), 0.0]
    fade.keyTimes  = [0.0, 0.25, 1.0]
    fade.duration  = duration
    fade.fillMode  = .forwards
    fade.beginTime = now
    return fade
}

if cfg.modes.contains(.rings) {
    let diameter = cfg.ringMaxRadius * 2
    for i in 0..<cfg.ringCount {
        let ring = CAShapeLayer()
        ring.bounds      = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        ring.position    = local
        ring.path        = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.fillColor   = NSColor.clear.cgColor
        ring.strokeColor = cfg.color.cgColor
        ring.lineWidth   = cfg.lineWidth
        ring.opacity     = 0
        content.layer?.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue      = cfg.ringStartRadius / cfg.ringMaxRadius
        scale.toValue        = 1.0
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values   = [0.0, 0.9, 0.0]
        fade.keyTimes = [0.0, 0.25, 1.0]

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration   = cfg.animationDur
        group.beginTime  = now + Double(i) * cfg.ringStagger
        group.fillMode   = .forwards

        ring.add(group, forKey: "pulse")
    }
}

if cfg.modes.contains(.border) {
    // Thick stroke hugging the screen perimeter; widened so the border reads
    // clearly on large/4K monitors without making --line-width feel huge for rings.
    let borderWidth = cfg.lineWidth * 3
    let inset = borderWidth / 2
    let rect = CGRect(
        x: inset, y: inset,
        width: screen.frame.width - borderWidth,
        height: screen.frame.height - borderWidth
    )
    let border = CAShapeLayer()
    border.frame       = NSRect(origin: .zero, size: screen.frame.size)
    border.path        = CGPath(rect: rect, transform: nil)
    border.fillColor   = NSColor.clear.cgColor
    border.strokeColor = cfg.color.cgColor
    border.lineWidth   = borderWidth
    border.opacity     = 0
    content.layer?.addSublayer(border)
    border.add(fadeAnimation(duration: cfg.animationDur), forKey: "border")
}

if cfg.modes.contains(.crosshairs) {
    let w = cfg.lineWidth
    let horiz = CALayer()
    horiz.frame = CGRect(x: 0, y: local.y - w / 2, width: screen.frame.width, height: w)
    horiz.backgroundColor = cfg.color.cgColor
    horiz.opacity = 0
    content.layer?.addSublayer(horiz)
    horiz.add(fadeAnimation(duration: cfg.animationDur), forKey: "h")

    let vert = CALayer()
    vert.frame = CGRect(x: local.x - w / 2, y: 0, width: w, height: screen.frame.height)
    vert.backgroundColor = cfg.color.cgColor
    vert.opacity = 0
    content.layer?.addSublayer(vert)
    vert.add(fadeAnimation(duration: cfg.animationDur), forKey: "v")
}

window.orderFrontRegardless()
dlog("ordered window front; exiting in \(totalDuration)s")

DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
    exit(0)
}

app.run()
