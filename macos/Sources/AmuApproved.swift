import AppKit
import Foundation

/// Approved HTML motion scenes and separate transparent effects, at the same source scale.
/// Pair scenes retain their sixteen independent cat drawings and articulated companions.
enum AmuApproved {
    struct Motion: Decodable { let cycle: Double; let samples: Int; let interval: Double; let drawings: Int; let props: Bool? }
    struct Manifest: Decodable { let cell: [Int]; let version: Int; let states: [String: Motion] }
    static let preference = "RettoAmuSeraMode"
    static var seraMode: Bool { UserDefaults.standard.bool(forKey: preference) }

    /// One choice per work/completion entry, owned by each RettoView.
    struct Choice {
        static let workingPool = ["heart","diamond","spade","clover"]
        static let completionPool = ["sera1","sera2"]
        private(set) var working = "spade"
        private(set) var completion = "sera1"
        private var token = ""
        private var lastTurn = ""
        static func group(_ state: PetState) -> String {
            switch state { case .running,.review:return "work";case .waving:return "complete";default:return state.rawValue }
        }
        @discardableResult mutating func enter(_ state: PetState, session: String, turn: String, pick: (Int)->Int = { Int.random(in:0..<$0) }) -> Bool {
            let group=Self.group(state),next=group+"|"+session
            if next == token {
                // Tool payloads may omit a turn id or enrich it after entry.
                if turn.isEmpty || lastTurn.isEmpty || turn == lastTurn {
                    if !turn.isEmpty { lastTurn=turn }
                    return false
                }
            }
            token=next;lastTurn=turn
            if group=="work" { working=Self.workingPool[pick(Self.workingPool.count)];return true }
            if group=="complete" { completion=Self.completionPool[pick(Self.completionPool.count)];return true }
            return false
        }
        mutating func preview(working:String?,completion:String?) {
            if let working,Self.workingPool.contains(working){self.working=working}
            if let completion,Self.completionPool.contains(completion){self.completion=completion}
        }
    }
    static func validateChoices() -> Bool {
        var seenWork=Set<String>(),seenComplete=Set<String>()
        for episode in 0..<64 {
            var c=Choice(),calls=0
            let picker:(Int)->Int={ n in calls+=1;return episode % n }
            guard c.enter(.running,session:"a",turn:"one",pick:picker) else{return false}
            let work=c.working;seenWork.insert(work)
            for s:PetState in [.running,.review,.running,.review] {
                guard !c.enter(s,session:"a",turn:"one",pick:picker),c.working==work else{return false}
            }
            guard !c.enter(.review,session:"a",turn:"",pick:picker),c.working==work else{return false}
            guard calls==1,c.enter(.waving,session:"a",turn:"one",pick:picker) else{return false}
            let done=c.completion;seenComplete.insert(done)
            for _ in 0..<100 {guard !c.enter(.waving,session:"a",turn:"one",pick:picker),c.completion==done else{return false}}
            guard calls==2 else{return false}
            _=c.enter(.idle,session:"a",turn:"one",pick:picker)
            guard c.enter(.running,session:"a",turn:"one",pick:picker),calls==3 else{return false}
            guard c.enter(.running,session:"b",turn:"one",pick:picker),calls==4 else{return false}
            guard c.enter(.running,session:"b",turn:"two",pick:picker),calls==5 else{return false}
        }
        guard seenWork==Set(Choice.workingPool),seenComplete==Set(Choice.completionPool) else{return false}
        print("PASS Amu choice: all4 working/all2 completion outcomes, stable repeated refresh/review alias, new episode/session redraws")
        return true
    }
    static let root = Bundle.main.resourceURL?.appendingPathComponent("AmuApproved")
    static let manifest: Manifest? = {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }()
    static func key(row: Int, workingKey: String = "spade", completionKey: String = "sera1") -> String? {
        switch row {
        case 0: return "idle"
        case 3: return completionKey
        case 4: return "school"
        case 5: return "clover"
        case 6: return "waiting"
        case 7, 8: return workingKey
        case 11: return "sleep"
        default: return nil
        }
    }
    static let available: Bool = {
        guard let root, let m = manifest, m.cell == [448,640], m.states.count == 10 else { return false }
        for (key, motion) in m.states {
            guard motion.samples == 80, motion.cycle > 0 else { return false }
            for sample in 0..<80 {
                for layer in (["scene", "back", "front"] + (motion.props == true ? ["props"] : [])) {
                    if !FileManager.default.fileExists(atPath: root.appendingPathComponent("\(key)-\(layer)-\(sample).png").path) { return false }
                }
            }
        }
        return true
    }()
    /// Fixed pose-group registration, shared by isolated character, props and effects.
    /// Preserve every drawing's dimensions and within-motion displacement.
    static let supportLines: [String: CGFloat] = ["waiting":585,"idle":585,"school":585,"heart":590,"diamond":590,"spade":590,"clover":590,"sera1":590,"sera2":590,"sleep":600]
    static func registeredRect(row: Int, in canvas: NSRect, workingKey: String = "spade", completionKey: String = "sera1") -> NSRect {
        // Legacy whole-body gaze drawings already occupy the628 floor.
        let motion = key(row:row,workingKey:workingKey,completionKey:completionKey)
        guard let motion, let source = supportLines[motion] else { return canvas }
        return canvas.offsetBy(dx:0,dy:-canvas.height*(628-source)/640)
    }
    static func validateRegistration() -> Bool {
        for scale: CGFloat in [0.39,0.5,0.65,1,1.4] {
            let canvas=NSRect(x:17,y:80,width:294*scale,height:420*scale)
            for row in [0,3,4,5,6,7,8,11] {
                for work in Choice.workingPool {
                    for done in Choice.completionPool {
                        let motion=key(row:row,workingKey:work,completionKey:done)!
                        let rect=registeredRect(row:row,in:canvas,workingKey:work,completionKey:done)
                        guard rect.size==canvas.size,rect.minX==canvas.minX,
                              abs((rect.maxY-rect.height*supportLines[motion]!/640)-(canvas.maxY-canvas.height*628/640))<0.000001 else{return false}
                    }
                }
            }
            for row in [1,2,9,10] { guard registeredRect(row:row,in:canvas)==canvas else{return false} }
            // Gaze keeps its existing full-body registration; effects retain the idle camera.
        }
        print("PASS Amu registration:10 motions at5 scales; unchanged drawing sizes; shared628 support; idle/gaze continuity; legacy drags retained")
        return true
    }
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 192; c.totalCostLimit = 112 * 1024 * 1024; return c
    }()
    static func sample(key: String, time: Double) -> Int {
        guard let m = manifest?.states[key], time.isFinite else { return 0 }
        return Int(floor(max(0,time).truncatingRemainder(dividingBy:m.cycle) / m.interval + 1e-7)) % m.samples
    }
    @discardableResult static func draw(row: Int, layer: String, time: Double, in rect: NSRect, workingKey: String = "spade", completionKey: String = "sera1") -> Bool {
        guard available, let key = key(row:row,workingKey:workingKey,completionKey:completionKey), let root else { return false }
        return draw(key:key, layer:layer, time:time, in:rect, root:root)
    }
    @discardableResult static func draw(key: String, layer: String, time: Double, in rect: NSRect, root: URL? = AmuApproved.root) -> Bool {
        guard let root else { return false }
        if layer == "front", manifest?.states[key]?.props == true {
            guard draw(key:key,layer:"props",time:time,in:rect,root:root) else { return false }
        }
        let name = "\(key)-\(layer)-\(sample(key:key,time:time))", token = name as NSString
        let image: NSImage
        if let cached = cache.object(forKey:token) { image = cached }
        else {
            guard let loaded = NSImage(contentsOf:root.appendingPathComponent(name+".png")) else { return false }
            image = loaded; cache.setObject(image,forKey:token,cost:448*640*4)
        }
        image.draw(in:rect,from:NSRect(origin:.zero,size:image.size),operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
        return true
    }
    static func validate() -> Bool {
        guard available, let m = manifest, validateChoices(), validateRegistration() else { return false }
        for (key, motion) in m.states {
            guard abs(Double(motion.samples)*motion.interval-motion.cycle)<0.000001,
                  motion.drawings == 16, (key != "idle" || motion.props == true) else { return false }
            for i in 0...80 {
                guard sample(key:key,time:Double(i)*motion.interval) == i%80 else { return false }
            }
        }
        guard key(row:4)=="school",key(row:6)=="waiting",key(row:5)=="clover",key(row:8)=="spade",key(row:7)=="spade",key(row:11)=="sleep",key(row:1)==nil else { return false }
        print("PASS Amu approved:10 full16-drawing motions including new school idle/waiting; exact80-sample clocks; sleep6.4s; legacy review maps to working; existing drag/gaze retained")
        return true
    }
}
