import UIKit

/// Shown once on first launch, and any time the ? button is tapped.
final class GuideOverlayView: UIView {

    private let scroll = UIScrollView()
    private let card = UIView()
    var onDismiss: (() -> Void)?

    private struct Item {
        let symbol: String
        let title: String
        let detail: String
    }

    private let items: [Item] = [
        Item(symbol: "hand.tap",
             title: "Tap the top of the screen",
             detail: "Anywhere near the notch or Dynamic Island shows the controls. Tap again to hide."),
        Item(symbol: "arrow.left",
             title: "Swipe in from the left edge",
             detail: "Goes back a page. Swipe in from the right edge to go forward."),
        Item(symbol: "arrow.down",
             title: "Scroll down to read",
             detail: "The control bar gets out of the way on its own while you scroll."),
        Item(symbol: "hand.point.up.left",
             title: "Two-finger tap",
             detail: "Shows the controls from anywhere, if the top of the screen is awkward to reach."),
        Item(symbol: "arrow.up.left.and.arrow.down.right",
             title: "Full-bleed button",
             detail: "Switches between filling the whole screen and staying clear of the Dynamic Island.")
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = UIColor.black.withAlphaComponent(0.82)

        // Five rows plus a title and a button do not fit in landscape, or at large
        // Dynamic Type. Without this the "Got it" button ends up off-screen and there
        // is no other way out of the overlay.
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        addSubview(scroll)

        card.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(card)

        let title = UILabel()
        title.text = "How to use SlimRead"
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [title])
        stack.axis = .vertical
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        for item in items {
            stack.addArrangedSubview(makeRow(item))
        }

        let button = UIButton(type: .system)
        button.setTitle("Got it", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.setTitleColor(.black, for: .normal)
        button.backgroundColor = .white
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        button.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        stack.addArrangedSubview(button)
        stack.setCustomSpacing(28, after: items.isEmpty ? title : stack.arrangedSubviews[stack.arrangedSubviews.count - 2])

        // Both update channels in one line. The app version only changes when a build is
        // sideloaded; the tweaks stamp changes on its own whenever tweaks/ is pushed.
        let footer = UILabel()
        footer.text = Self.versionLine
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = UIColor.white.withAlphaComponent(0.4)
        footer.textAlignment = .center
        footer.numberOfLines = 0
        stack.addArrangedSubview(footer)
        stack.setCustomSpacing(16, after: button)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            card.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            card.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            card.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            card.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),

            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
    }

    /// Keeps the card centred while it fits, and lets it scroll from the top once it
    /// does not. Simpler than fighting constraint priorities for the same effect.
    override func layoutSubviews() {
        super.layoutSubviews()
        let slack = max(0, scroll.bounds.height - scroll.contentSize.height) / 2
        if scroll.contentInset.top != slack {
            scroll.contentInset = UIEdgeInsets(top: slack, left: 0, bottom: 0, right: 0)
        }
    }

    private func makeRow(_ item: Item) -> UIView {
        let icon = UIImageView(
            image: UIImage(systemName: item.symbol,
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        )
        icon.tintColor = .white
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let title = UILabel()
        title.text = item.title
        title.font = .systemFont(ofSize: 16, weight: .medium)
        title.textColor = .white
        title.numberOfLines = 0

        let detail = UILabel()
        detail.text = item.detail
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = UIColor.white.withAlphaComponent(0.65)
        detail.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 3

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .top
        return row
    }

    /// e.g. "SlimRead 1.03 (7) - tweaks 1 Aug 03:14"
    ///
    /// Nothing else in the app reports either number, which makes "did my update
    /// actually land" unanswerable from the phone. The two move independently: the
    /// version needs a sideload, the tweaks stamp updates by itself on next launch.
    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"

        var line = "SlimRead \(version) (\(build))"

        if let updated = TweaksLoader.lastUpdated {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM HH:mm"
            line += "  -  tweaks \(formatter.string(from: updated))"
        } else {
            line += "  -  built-in tweaks"
        }

        return line
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }

    func present(in parent: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        alpha = 0
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
        UIView.animate(withDuration: 0.25) { self.alpha = 1 }
    }

    func dismiss() {
        UIView.animate(withDuration: 0.25) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}
