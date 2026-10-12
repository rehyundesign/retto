import Foundation

/// Pose selection follows elapsed time; late callbacks do not extend the walk cycle.
enum ChristmasMotion {
    static func position(elapsed: Double, durations: [Double]) -> (frame: Int, cycles: Int) {
        guard !durations.isEmpty, durations.allSatisfy({ $0.isFinite && $0 > 0 }) else { return (0, 0) }
        let cycle = durations.reduce(0, +)
        let time = max(0, elapsed)
        let cycles = Int(floor((time + 1e-9) / cycle))
        var phase = max(0, time - Double(cycles) * cycle)
        var frame = 0
        while frame < durations.count - 1 && phase + 1e-9 >= durations[frame] {
            phase -= durations[frame]
            frame += 1
        }
        return (frame, cycles)
    }
}
