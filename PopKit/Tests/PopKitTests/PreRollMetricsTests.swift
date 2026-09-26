import Testing
@testable import PopKit

/// Covers `PreRollMetrics`: what each fold found on the page it opened, how long until that
/// page moved, and how many session minutes the book used.
struct PreRollMetricsTests {
    @Test func startsEmpty() {
        let metrics = PreRollMetrics()
        #expect(metrics.folds == 0)
        #expect(metrics.clipReadyAtFold == 0)
        #expect(metrics.medianFoldToMotionMs == nil)
        #expect(metrics.summary == "folds 0 · loop ready 0 · live 0 · cold 0 · fold→motion p50 – · session 0.0 min")
    }

    @Test func countsWhatEachFoldFound() {
        var metrics = PreRollMetrics()
        metrics.folded(to: .clip)
        metrics.folded(to: .clip)
        metrics.folded(to: .live)
        metrics.folded(to: .preparing)
        metrics.folded(to: .cold)
        #expect(metrics.folds == 5)
        #expect(metrics.clipReadyAtFold == 2)
        #expect(metrics.liveAtFold == 2) // live, or still preparing hidden (revealed on its first frame)
        #expect(metrics.coldAtFold == 1)
    }

    @Test func foldToMotionIsTheMedianOfEveryFold() {
        var metrics = PreRollMetrics()
        metrics.moved(afterMs: 900)
        metrics.moved(afterMs: 120)
        metrics.moved(afterMs: 4_800)
        #expect(metrics.medianFoldToMotionMs == 900)
        metrics.moved(afterMs: -5) // clamped
        #expect(metrics.foldToMotionMs == [900, 120, 4_800, 0])
    }

    @Test func sessionMinutesAccumulateAcrossSessions() {
        var metrics = PreRollMetrics()
        metrics.addSessionTime(seconds: 90)
        metrics.addSessionTime(seconds: 30)
        metrics.addSessionTime(seconds: -4) // ignored
        #expect(metrics.sessionMinutes == 2)
    }

    @Test func theSummaryReadsInOneLine() {
        var metrics = PreRollMetrics()
        metrics.folded(to: .clip)
        metrics.folded(to: .cold)
        metrics.moved(afterMs: 150)
        metrics.moved(afterMs: 5_200)
        metrics.addSessionTime(seconds: 150)
        #expect(metrics.summary == "folds 2 · loop ready 1 · live 0 · cold 1 · fold→motion p50 5.2 s · session 2.5 min")
    }
}
