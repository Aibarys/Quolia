import UIKit

/// Drives perfectly smooth, sub-pixel auto scrolling with a display link
/// (up to 120 Hz on ProMotion displays).
final class AutoScrollEngine: NSObject {
    weak var scrollView: UIScrollView?
    /// Scrolling speed in points per second.
    var pointsPerSecond: CGFloat = 30
    /// Content offset at which scrolling stops (end of chapter).
    var stopOffset: CGFloat = .greatestFiniteMagnitude

    var onReachEnd: (() -> Void)?
    var onTick: (() -> Void)?

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var position: CGFloat = 0

    var isRunning: Bool { link != nil }

    func start() {
        guard let scrollView, link == nil else { return }
        position = scrollView.contentOffset.y
        lastTimestamp = 0
        let link = CADisplayLink(target: WeakProxy(self), selector: #selector(WeakProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// Re-syncs with a manual scroll position (after the user drags).
    func resync() {
        position = scrollView?.contentOffset.y ?? position
        lastTimestamp = 0
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let scrollView else { stop(); return }
        if lastTimestamp == 0 { lastTimestamp = link.targetTimestamp; return }
        let dt = min(link.targetTimestamp - lastTimestamp, 0.05)
        lastTimestamp = link.targetTimestamp
        position += pointsPerSecond * CGFloat(dt)
        if position >= stopOffset {
            position = stopOffset
            scrollView.contentOffset.y = position
            stop()
            onReachEnd?()
            return
        }
        scrollView.contentOffset.y = position
        onTick?()
    }

    deinit { link?.invalidate() }
}

/// Breaks the CADisplayLink → target retain cycle.
private final class WeakProxy: NSObject {
    weak var engine: AutoScrollEngine?
    init(_ engine: AutoScrollEngine) { self.engine = engine }
    @objc func tick(_ link: CADisplayLink) {
        if let engine { engine.tick(link) } else { link.invalidate() }
    }
}

enum ReadingSpeed {
    static let wpmRange: ClosedRange<Double> = 80...600
    static let step: Double = 20

    /// Converts words-per-minute into scrolling points-per-second for the current layout.
    static func pointsPerSecond(wpm: Double, textHeight: CGFloat, words: Int) -> CGFloat {
        guard words > 0, textHeight > 0 else { return CGFloat(wpm / 60) * 6 }
        let pointsPerWord = textHeight / CGFloat(words)
        return CGFloat(wpm / 60) * pointsPerWord
    }
}
