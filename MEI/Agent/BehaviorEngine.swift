import Foundation

struct BehaviorEngine {
    /// Sample a realistic reply delay based on the contact's style profile.
    static func sampleReplyDelay(for style: StyleProfile?) -> TimeInterval {
        // TODO: Restore realistic delays before production
        // let meanMinutes = style?.behavior?.responseTimeMeanMinutes ?? 3.0
        // let stdMinutes = style?.behavior?.responseTimeStdMinutes ?? 2.0
        // let normalSample = randomNormal(mean: 0, std: 1)
        // let logMean = log(meanMinutes) - 0.5 * log(1 + (stdMinutes * stdMinutes) / (meanMinutes * meanMinutes))
        // let logStd = sqrt(log(1 + (stdMinutes * stdMinutes) / (meanMinutes * meanMinutes)))
        // let delayMinutes = exp(logMean + logStd * normalSample)
        // let delaySeconds = max(30, min(delayMinutes * 60, 1800))
        let delaySeconds = Double.random(in: 5.0...10.0)

        return delaySeconds
    }

    /// Delay between messages in a multi-message burst (1-4 seconds).
    static func burstDelay() -> TimeInterval {
        return Double.random(in: 1.0...4.0)
    }

    /// Whether the agent should send multiple messages based on style profile.
    static func shouldSendMultipleMessages(style: StyleProfile?) -> Bool {
        let tendency = style?.behavior?.multiMessageTendency ?? 0.3
        return Double.random(in: 0...1) < tendency
    }

    /// Check if current time is within the contact's typical active hours.
    static func isTypicalActiveTime(style: StyleProfile?) -> Bool {
        guard let hours = style?.timePatterns?.mostActiveHours, !hours.isEmpty else {
            return true
        }
        let currentHour = Calendar.current.component(.hour, from: Date())
        return hours.contains(currentHour)
    }

    // MARK: - Helpers

    /// Box-Muller transform for normal distribution sampling.
    private static func randomNormal(mean: Double, std: Double) -> Double {
        let u1 = Double.random(in: 0.001...1.0) // avoid log(0)
        let u2 = Double.random(in: 0...1)
        let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        return mean + std * z
    }
}
