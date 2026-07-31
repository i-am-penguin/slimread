import UIKit

/// Shown once on first launch, and any time the ? button is tapped.
final class GuideOverlayView: UIView {

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

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

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

        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])
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
