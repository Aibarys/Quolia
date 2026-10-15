import UIKit

/// Non-editable, selectable TextKit 1 text view used for every reading surface.
final class ReaderTextView: UITextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isEditable = false
        isSelectable = true
        backgroundColor = .clear
        dataDetectorTypes = []
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        textDragInteraction?.isEnabled = false
        alwaysBounceVertical = true
        smartInsertDeleteType = .no
        accessibilityTraits.insert(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Small marker in the page margin indicating that a highlight carries a note.
final class NoteMarkerView: UIControl {
    let highlightID: UUID
    var onTap: ((UUID) -> Void)?

    init(highlightID: UUID, color: UIColor) {
        self.highlightID = highlightID
        super.init(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
        let image = UIImageView(image: UIImage(systemName: "text.bubble.fill",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        image.tintColor = color
        image.frame = bounds
        image.contentMode = .center
        image.isUserInteractionEnabled = false
        addSubview(image)
        accessibilityLabel = String(localized: "Note")
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() {
        Haptics.selection()
        onTap?(highlightID)
    }
}

/// End-of-chapter footer in scroll mode.
final class ChapterFooterView: UIView {
    private let ornament = UILabel()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    var onTap: (() -> Void)?
    private let defaultHint: String

    init(nextTitle: String?, theme: ReaderTheme, font: UIFont) {
        defaultHint = nextTitle == nil
            ? String(localized: "You've reached the end of the book")
            : String(localized: "Pull up or tap to continue")
        super.init(frame: .zero)
        ornament.text = "⁂"
        ornament.textColor = theme.secondaryText
        ornament.font = font.withSize(18)
        ornament.textAlignment = .center

        titleLabel.text = nextTitle.map { String(localized: "Next: \($0)") } ?? String(localized: "The End")
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = theme.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        hintLabel.text = defaultHint
        hintLabel.font = UIFont.systemFont(ofSize: 13)
        hintLabel.textColor = theme.secondaryText
        hintLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [ornament, titleLabel, hintLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: topAnchor),
        ])
        if nextTitle != nil {
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        }
        isAccessibilityElement = true
        accessibilityLabel = titleLabel.text
        accessibilityTraits = nextTitle == nil ? .staticText : .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setArmed(_ armed: Bool) {
        let text = armed ? String(localized: "Release to continue") : defaultHint
        guard hintLabel.text != text else { return }
        hintLabel.text = text
        if armed { Haptics.light() }
    }

    @objc private func tapped() { onTap?() }
}

/// One page in paged mode: a fixed-size text view showing one page of a chapter.
/// The text view has its own TextKit stack (see `ChapterLayout.makePageStack`), so its
/// character indices are page-local: chapter index = local index + `characterOffset`.
final class TextPageViewController: UIViewController {
    let layout: ChapterLayout
    let pageIndex: Int
    let textView: ReaderTextView
    let characterOffset: Int
    private let stack: PageStack?
    private let theme: ReaderTheme

    init(layout: ChapterLayout, pageIndex: Int, frame: CGRect, theme: ReaderTheme, delegate: UITextViewDelegate) {
        self.layout = layout
        self.pageIndex = pageIndex
        self.theme = theme
        stack = layout.makePageStack(pageIndex)
        // Without its own stack the page falls back to the shared container: same text, but not selectable.
        characterOffset = stack?.characterOffset ?? 0
        textView = ReaderTextView(frame: frame, textContainer: stack?.container ?? layout.containers[pageIndex])
        super.init(nibName: nil, bundle: nil)
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.textContainerInset = .zero
        textView.delegate = delegate
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        view.addSubview(textView)
    }

    /// The page's range in chapter coordinates.
    var characterRange: NSRange { layout.range(ofPage: pageIndex) }

    /// Converts a chapter range to this text view's coordinates, clipped to the text it holds.
    func localRange(_ chapterRange: NSRange) -> NSRange? {
        let held = NSRange(location: characterOffset, length: textView.textStorage.length)
        let clipped = NSIntersectionRange(chapterRange, held)
        guard clipped.length > 0 else { return nil }
        return NSRange(location: clipped.location - characterOffset, length: clipped.length)
    }

    /// Draws highlight marks given in chapter coordinates.
    func applyMarks(_ marks: [ReaderLayoutManager.Mark]) {
        guard let layoutManager = stack?.layoutManager else { return }
        layoutManager.marks = marks.compactMap { mark in
            localRange(mark.range).map { ReaderLayoutManager.Mark(range: $0, color: mark.color) }
        }
    }
}
