/// Picking an animation's frame by the clock, so every copy of an emoji plays in step.
public enum FrameTiming {
    /// The frame showing at `time` (seconds, any epoch) when frames last `durations` each and
    /// the animation loops. Frames that claim no time get the 0.1 s browsers give them.
    public static func frame(at time: Double, durations: [Double]) -> Int {
        let durations = durations.map { $0 > 0.01 ? $0 : 0.1 }
        let total = durations.reduce(0, +)
        guard total > 0 else { return 0 }
        var remaining = time.truncatingRemainder(dividingBy: total)
        if remaining < 0 { remaining += total }
        for (index, duration) in durations.enumerated() {
            if remaining < duration { return index }
            remaining -= duration
        }
        return durations.count - 1
    }
}
