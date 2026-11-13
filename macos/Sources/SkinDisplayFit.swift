import AppKit

/// Display-only fitting: keep approved pixels, anatomy, pose timing and effects intact.
/// Coordinates are measured in the 448 × 640 source canvas, from its top-left.
enum SkinDisplayFit {
    struct Profile {
        let scale: CGFloat
        let sourceGroundY: CGFloat
    }

    // Fixed per-pose-group transforms, calibrated from Retto's fur face rather than
    // the atlas bounds, hat, companion, or effect extent. One transform per row
    // preserves the original in-row motion and never resizes individual frames.
    private static let hanaProfiles: [Int: Profile] = [
        0: Profile(scale: 1.12, sourceGroundY: 600),  // seated idle
        1: Profile(scale: 1.40, sourceGroundY: 560),  // right gait
        2: Profile(scale: 1.32, sourceGroundY: 560),  // left gait
        3: Profile(scale: 1.06, sourceGroundY: 606),  // greeting
        4: Profile(scale: 1.08, sourceGroundY: 606),  // jump; retain airborne offsets
        5: Profile(scale: 1.12, sourceGroundY: 606),
        6: Profile(scale: 1.10, sourceGroundY: 606),
        7: Profile(scale: 1.10, sourceGroundY: 606),
        8: Profile(scale: 0.91, sourceGroundY: 606),  // larger, lowered face at the work prop
        11: Profile(scale: 0.90, sourceGroundY: 566)  // curled pose has its own floor
    ]
    private static let jeanneProfiles: [Int: Profile] = [
        0: Profile(scale: 1.04, sourceGroundY: 632),
        1: Profile(scale: 1.18, sourceGroundY: 560),
        2: Profile(scale: 1.22, sourceGroundY: 544),
        3: Profile(scale: 1.00, sourceGroundY: 638),
        4: Profile(scale: 1.00, sourceGroundY: 638),
        5: Profile(scale: 1.04, sourceGroundY: 638),
        6: Profile(scale: 1.04, sourceGroundY: 632),
        7: Profile(scale: 0.98, sourceGroundY: 628),
        8: Profile(scale: 1.04, sourceGroundY: 632),
        9: Profile(scale: 1.00, sourceGroundY: 594),
        10: Profile(scale: 1.00, sourceGroundY: 594),
        11: Profile(scale: 0.85, sourceGroundY: 566)
    ]

    static func profile(_ raw: String, row: Int) -> Profile? {
        switch raw {
        case "hana":
            // Gaze cells retain the seated body. Reuse its camera so cursor entry
            // and gaze reset cannot change the whole character's apparent scale.
            return hanaProfiles[row == 9 || row == 10 ? 0 : row]
        case "jeanne": return jeanneProfiles[row]
        default: return nil
        }
    }

    static func rect(for skin: PetSkin, row: Int, in canvas: NSRect) -> NSRect {
        rect(raw: skin.rawValue, row: row, in: canvas)
    }

    static func rect(raw: String, row: Int, in canvas: NSRect) -> NSRect {
        guard let p = profile(raw, row: row) else { return canvas }
        let size = NSSize(width: canvas.width * p.scale, height: canvas.height * p.scale)
        let ground = canvas.maxY - canvas.height * 628 / 640
        return NSRect(x: canvas.midX - size.width / 2,
                      y: ground - size.height * (1 - p.sourceGroundY / 640),
                      width: size.width, height: size.height)
    }

    static func selfTest() -> Bool {
        for factor: CGFloat in [0.39, 0.5, 1, 1.4] {
            let canvas = NSRect(x: 13, y: 257, width: 224 * factor, height: 320 * factor)
            for raw in ["hana", "jeanne"] {
                for row in 0..<12 {
                    guard let p = profile(raw, row: row) else { return false }
                    let fit = rect(raw: raw, row: row, in: canvas)
                    let sourceGround = fit.maxY - fit.height * p.sourceGroundY / 640
                    let targetGround = canvas.maxY - canvas.height * 628 / 640
                    guard abs(sourceGround - targetGround) < 0.000001,
                          abs(fit.width / canvas.width - p.scale) < 0.000001,
                          abs(fit.width / fit.height - canvas.width / canvas.height) < 0.000001,
                          abs(fit.midX - canvas.midX) < 0.000001 else { return false }
                }
                // A jump has a fixed row transform; its source displacement is preserved.
                let jump = rect(raw: raw, row: 4, in: canvas)
                guard let p = profile(raw, row: 4) else { return false }
                let lift = jump.height * 80 / 640
                guard abs(lift - canvas.height * 80 / 640 * p.scale) < 0.000001 else { return false }
            }
            for raw in ["classic", "amuRan", "chocolatHeart", "pichiPitch", "christmas"] {
                guard rect(raw: raw, row: 0, in: canvas) == canvas else { return false }
            }
        }
        guard let seated = profile("hana", row: 0), [9, 10].allSatisfy({ row in
            guard let gaze = profile("hana", row: row) else { return false }
            return gaze.scale == seated.scale && gaze.sourceGroundY == seated.sourceGroundY
        }) else { return false }
        // Source fur-face spans are representative visual calibration anchors at 2x.
        // They exclude hats/companions. Front, side and curled views have distinct
        // original-Retto references; this is not an original-anatomy certificate.
        let anchors: [(String, Int, CGFloat, CGFloat)] = [
            ("hana",0,210,236), ("hana",7,215,236), ("hana",8,259,236),
            ("hana",6,212,236), ("hana",3,221,236), ("hana",4,218,236),
            ("hana",5,211,236), ("hana",1,105,152), ("hana",2,112,152),
            ("hana",11,171,152), ("jeanne",0,224,236), ("jeanne",7,240,236),
            ("jeanne",8,222,236), ("jeanne",6,230,236), ("jeanne",3,233,236),
            ("jeanne",4,234,236), ("jeanne",5,224,236), ("jeanne",1,127,152),
            ("jeanne",2,124,152), ("jeanne",11,182,152)
        ]
        for (raw, row, source, reference) in anchors {
            guard let p = profile(raw, row: row), abs(p.scale * source / reference - 1) <= 0.05 else { return false }
        }
        print("Display fit: 24 pose-row profiles; representative calibration arithmetic, floor, aspect and jump displacement checks passed")
        return true
    }
}
