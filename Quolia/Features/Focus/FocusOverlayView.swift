import UIKit

/// Dims everything except a focus rect.
///
/// While text scrolls underneath, the cut-out tracks its line exactly; when the
/// focused line or paragraph changes, the cut-out glides to the new one. This is
/// done by decaying a "residual" offset on a display link instead of animating
/// the path, so tracking and gliding compose without fighting each other.
final class FocusOverlayView: UIView {
    private let shape = CAShapeLayer()
    private var target: CGRect?
    private var residual = CGRect.zero // displayed - target, component-wise
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    var dimColor: UIColor = .black.withAlphaComponent(0.6) {
        didSet { shape.fillColor = dimColor.cgColor }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.fillRule = .evenOdd
        shape.fillColor = dimColor.cgColor
        layer.addSublayer(shape)
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        render()
    }

    var isShowingFocus: Bool { target != nil }

    /// - Parameters:
    ///   - rect: Focus rect in this view's coordinates, or nil to hide.
    ///   - unitChanged: True when focus moved to a different line/paragraph (glide);
    ///     false when the same unit simply moved with scrolling content (track).
    func update(_ rect: CGRect?, unitChanged: Bool, animated: Bool) {
        guard let rect else {
            if target != nil {
                target = nil
                UIView.animate(withDuration: animated ? 0.3 : 0) { self.alpha = 0 }
            }
            stopLink()
            return
        }
        let padded = rect.insetBy(dx: -10, dy: -6)
        if let current = displayedRect, unitChanged, animated, alpha > 0 {
            residual = CGRect(x: current.minX - padded.minX, y: current.minY - padded.minY,
                              width: current.width - padded.width, height: current.height - padded.height)
            startLink()
        } else if unitChanged {
            residual = .zero
        }
        target = padded
        render()
        if alpha == 0 {
            UIView.animate(withDuration: animated ? 0.35 : 0) { self.alpha = 1 }
        }
    }

    private var displayedRect: CGRect? {
        guard let target else { return nil }
        return CGRect(x: target.minX + residual.minX, y: target.minY + residual.minY,
                      width: target.width + residual.width, height: target.height + residual.height)
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = UIBezierPath(rect: bounds.insetBy(dx: -40, dy: -40))
        if let rect = displayedRect {
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: 10))
        }
        shape.path = path.cgPath
        CATransaction.commit()
    }

    private func startLink() {
        guard link == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: FocusLinkProxy(self), selector: #selector(FocusLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(now - lastTimestamp, 0.05)
        lastTimestamp = now
        let decay = CGFloat(exp(-dt / 0.075))
        residual = CGRect(x: residual.minX * decay, y: residual.minY * decay,
                          width: residual.width * decay, height: residual.height * decay)
        if abs(residual.minX) + abs(residual.minY) + abs(residual.width) + abs(residual.height) < 0.5 {
            residual = .zero
            stopLink()
        }
        render()
    }

    deinit { link?.invalidate() }
}

private final class FocusLinkProxy: NSObject {
    weak var view: FocusOverlayView?
    init(_ view: FocusOverlayView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) {
        if let view { view.tick(link) } else { link.invalidate() }
    }
}
