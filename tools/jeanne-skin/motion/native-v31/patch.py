from pathlib import Path
p=Path(__file__).parent;s=p/'Sources'
def edit(n,a,b):
 f=s/n;t=f.read_text();assert a in t,(n,a);f.write_text(t.replace(a,b,1))
edit('Geometry.swift','    case pichiPitch\n','    case pichiPitch\n    case jeanne\n')
edit('Geometry.swift','        case .pichiPitch: return "피치피치핏치"','        case .pichiPitch: return "피치피치핏치"\n        case .jeanne: return "신의괴도 잔느"')
edit('Geometry.swift','        case .pichiPitch: return "pichi-character"','        case .pichiPitch: return "pichi-character"\n        case .jeanne: return "jeanne-character"')
edit('Geometry.swift','        if self == .pichiPitch { return PichiSkin.available }','        if self == .jeanne { return JeanneSkin.available }\n        if self == .pichiPitch { return PichiSkin.available }')
edit('AppDelegate.swift','        if skin == .pichiPitch { return PichiSkin.placeholder }','        if skin == .jeanne { return JeanneSkin.placeholder }\n        if skin == .pichiPitch { return PichiSkin.placeholder }')
edit('Tones.swift','    if skin == .pichiPitch { return PichiSkin.animation(animation) }','    if skin == .jeanne { return JeanneSkin.animation(animation) }\n    if skin == .pichiPitch { return PichiSkin.animation(animation) }')
edit('PetView.swift','    private var pichiEpoch =','    private var jeanneEpoch = ProcessInfo.processInfo.systemUptime\n    private var jeannePreviewTime: Double?\n    func setJeanneTimeForPreview(_ time: Double) {\n        jeannePreviewTime = time\n        if let a = currentAnimation { frameIndex = JeanneSkin.position(row: a.row, time: time).frame }\n        needsDisplay = true\n    }\n    private var pichiEpoch =')
edit('PetView.swift','        if skin == .pichiPitch {\n            pichiEpoch =','        if skin == .jeanne {\n            jeanneEpoch = ProcessInfo.processInfo.systemUptime - JeanneSkin.elapsed(row: animation.row, frame: frameIndex, cycles: completedCycles)\n        }\n        if skin == .pichiPitch {\n            pichiEpoch =')
edit('PetView.swift','skin == .hana || skin == .chocolatHeart || skin == .pichiPitch','skin == .jeanne || skin == .hana || skin == .chocolatHeart || skin == .pichiPitch')
edit('PetView.swift','        if skin == .pichiPitch {\n            let p =','        if skin == .jeanne {\n            if dragRun == nil && lookDirection != nil { needsDisplay = true; return }\n            let p = JeanneSkin.position(row: animation.row, time: ProcessInfo.processInfo.systemUptime - jeanneEpoch)\n            frameIndex = p.frame; completedCycles = p.cycles; needsDisplay = true\n        } else if skin == .pichiPitch {\n            let p =')
edit('PetView.swift','        if skin == .pichiPitch {\n            PichiSkin.drawCharacter','        if skin == .jeanne {\n            JeanneSkin.drawCharacter(row: row, frame: column, in: petRect)\n        } else if skin == .pichiPitch {\n            PichiSkin.drawCharacter')
edit('main.swift','if CommandLine.arguments.contains("--pichi-self-test")','if CommandLine.arguments.contains("--jeanne-self-test") { exit(JeanneSkin.validate() ? 0 : 1) }\nif let i = CommandLine.arguments.firstIndex(of: "--render-jeanne-preview"), i + 1 < CommandLine.arguments.count { exit(renderJeannePreview(to: CommandLine.arguments[i + 1])) }\n\nif CommandLine.arguments.contains("--pichi-self-test")')
t=(s/'PichiSkin.swift').read_text();t=t.replace('PichiSkin','JeanneSkin').replace('PichiFrames','JeanneFrames').replace('renderPichiPreview','renderJeannePreview').replace('setPichiTimeForPreview','setJeanneTimeForPreview').replace('.pichiPitch','.jeanne').replace('pichi','jeanne')
# Use the approved integrated image cells: no independently redrawn overlay effects.
a=t.index('    struct Cell:');b=t.index('    private static let cache:')
t=t[:a]+'''    struct State: Decodable { let id: String; let row: Int; let cycle: Double; let times: [Double]; let files: [String] }
    struct Manifest: Decodable { let states: [State] }
    static let manifest: Manifest? = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "JeanneFrames"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()
'''+t[b:]
a=t.index('    static func elapsed(');b=t.index('\n}\n\nfunc renderJeannePreview')
t=t[:a]+'''    static func elapsed(row: Int, frame: Int, cycles: Int) -> Double {
        guard let s = state(row: row) else { return 0 }
        return Double(cycles) * s.cycle + s.times.prefix(frame).reduce(0,+)
    }
    static func position(row: Int, time: Double) -> (frame: Int, cycles: Int) {
        guard let s = state(row: row) else { return (0,0) }
        let t = max(0,time), cycles = Int(t / s.cycle); var q = t.truncatingRemainder(dividingBy: s.cycle)
        for (i,d) in s.times.enumerated() { if q < d { return (i,cycles) }; q -= d }
        return (s.files.count-1,cycles)
    }
    static func animation(_ a: Animation) -> Animation {
        guard let s = state(row: a.row) else { return a }
        return Animation(row: a.row, frames: s.files.count, interval: s.cycle / Double(s.files.count), cycleLimit: a.cycleLimit, kicker: a.kicker, title: a.title, tone: a.tone)
    }
    static func image(_ f: String) -> NSImage? {
        if let im = cache.object(forKey: f as NSString) { return im }
        guard let url = Bundle.main.url(forResource: f, withExtension: nil, subdirectory: "JeanneFrames"), let im = NSImage(contentsOf: url) else { return nil }
        cache.setObject(im, forKey: f as NSString); return im
    }
    static func drawCharacter(row: Int, frame: Int, in rect: NSRect) {
        let file: String
        if row == 9 || row == 10 { file = "gaze-\\((row-9)*8+frame).png" }
        else { guard let s = state(row: row) else { return }; file = s.files[frame % s.files.count] }
        image(file)?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    }
    static func validate() -> Bool {
        guard let m = manifest, m.states.count == 10 else { return false }
        for s in m.states {
            guard s.files.count == 16, s.times.count == 16, abs(s.times.reduce(0,+)-s.cycle)<0.000001 else { return false }
            var elapsed = 0.0
            for (i,f) in s.files.enumerated() {
                guard image(f)?.size == NSSize(width:448,height:640), position(row:s.row,time:elapsed+0.00001).frame == i else { return false }
                elapsed += s.times[i]
            }
            guard position(row:s.row,time:s.cycle+0.00001).cycles == 1 else { return false }
        }
        for i in 0..<16 { guard image("gaze-\\(i).png")?.size == NSSize(width:448,height:640) else { return false } }
        print("{\\"jeanneOK\\":true,\\"cells\\":160,\\"gaze\\":16,\\"timing\\":\\"v31\\"}")
        return true
    }
'''+t[b:]
(s/'JeanneSkin.swift').write_text(t)
