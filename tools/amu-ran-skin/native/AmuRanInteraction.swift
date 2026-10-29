import AppKit
import Foundation

/// Partner poses and attachment positions share the character's state clock.
/// Breathing still advances while a gaze/preview holds the cat still.
enum AmuRanInteraction {
    struct Key: Decodable { let x: Double; let y: Double; let pose: Int }
    struct Track: Decodable { let cycle: Double; let side: String; let frames: [Key] }
    struct Plan: Decodable { let rows: [String: Track] }
    struct Sample { let side: String; let pose: Int; let point: NSPoint }

    static let plan: Plan? = {
        guard let url = Bundle.main.url(forResource: "interaction", withExtension: "json", subdirectory: "AmuRanFrames"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Plan.self, from: data),
              value.rows.count == 10, value.rows.values.allSatisfy({ track in
                  track.cycle > 0 && track.frames.count == 16 && ["left", "right", "sleep"].contains(track.side)
                  && track.frames.allSatisfy { $0.pose >= 0 && $0.pose < 8 && $0.x >= 12 && $0.x <= 346 && $0.y >= 12 && $0.y <= 538 }
              }) else { return nil }
        return value
    }()

    static func sample(row: Int, poseTime: Double, effectTime: Double, gazeDirection: Int? = nil) -> Sample? {
        guard poseTime.isFinite, effectTime.isFinite, let track = plan?.rows[String(row)] else { return nil }
        var side = track.side, pose: Int, x: Double, y: Double
        if gazeDirection != nil {
            side = "right"
            x = 315
            y = row == 3 ? 365 : 350
            pose = Int(floor(max(0, effectTime) / 0.8)) % 2
        } else {
            var phase = (max(0, poseTime) / track.cycle * 16).truncatingRemainder(dividingBy: 16)
            if abs(phase - phase.rounded()) < 1e-7 { phase = phase.rounded().truncatingRemainder(dividingBy: 16) }
            let index = Int(floor(phase))
            let a = track.frames[index], b = track.frames[(index + 1) % 16]
            let fraction = phase - floor(phase), u = fraction * fraction * (3 - 2 * fraction)
            x = a.x + (b.x - a.x) * u
            y = a.y + (b.y - a.y) * u
            pose = a.pose
        }
        let amount = side == "sleep" ? 0.4 : (pose == 3 ? 0.35 : 1.1)
        y += amount * sin(max(0, effectTime) * 2 * Double.pi / (side == "sleep" ? 6.4 : 1.6))
        return Sample(side: side, pose: pose, point: NSPoint(x: floor(x + 0.5), y: floor(y + 0.5)))
    }
}
