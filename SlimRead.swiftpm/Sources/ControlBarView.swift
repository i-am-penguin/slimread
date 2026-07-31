import UIKit

/// Bottom overlay bar. Hidden by default; slides up when the user taps the pill handle
/// or two-finger taps anywhere. Deliberately lives at the bottom so it is thumb-reachable
/// and never competes with the (absent) status bar area at the top.
final class ControlBarView: UIView {

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onReload: (() -> Void)?
    var onHome: (() -> Void)?
    var onToggleFullBleed: (() -> Void)?
    var onSubmit: ((String) -> Void)?
    var onInteraction: (() -> Void)?

    // MARK: - Subviews

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let backButton = ControlBarView.makeButton("chevron.left")
    private let forwardButton = ControlBarView.makeButton("chevron.right")
    private let reloadButton = ControlBarView.makeButton("arrow.clockwise")
    private let homeButton = ControlBarView.makeButton("house")
    private let fullBleedButton = ControlBarView.makeButton("arrow.up.left.and.arrow.down.right")

    let field: UITextField = {
        let f = UITextField()
        f.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        f.textColor = .white
        f.tintColor = .white
        f.font = .systemFont(ofSize: 15)
        f.layer.cornerRadius = 10
        f.layer.cornerCurve = .continuous
        f.keyboardType = .URL
        f.keyboardAppearance = .dark
        f.returnKeyType = .go
        f.autocapitalizationType = .none
        f.autocorrectionType = .no
        f.spellCheckingType = .no
        f.clearButtonMode = .whileEditing
        f.textAlignment = .center
        f.attributedPlaceholder = NSAttributedString(
            string: "Search or enter address",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        )
        let pad = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        f.leftView = pad
        f.leftViewMode = .always
        return f
    }()

    private let barHeight: CGFloat = 52

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear

        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        let navStack = UIStackView(arrangedSubviews: [backButton, forwardButton])
        navStack.spacing = 4

        let actionStack = UIStackView(arrangedSubviews: [reloadButton, homeButton, fullBleedButton])
        actionStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [navStack, field, actionStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),

            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.heightAnchor.constraint(equalToConstant: 40),

            field.heightAnchor.constraint(equalToConstant: 36)
        ])

        field.delegate = self
        field.addTarget(self, action: #selector(noteInteraction), for: .editingChanged)

        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(tapForward), for: .touchUpInside)
        reloadButton.addTarget(self, action: #selector(tapReload), for: .touchUpInside)
        homeButton.addTarget(self, action: #selector(tapHome), for: .touchUpInside)
        fullBleedButton.addTarget(self, action: #selector(tapFullBleed), for: .touchUpInside)
    }

    // MARK: - Sizing
    //
    // Height grows to swallow the home-indicator inset so the blur reaches the screen edge.

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: barHeight + safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }

    // MARK: - State in

    func setCanGoBack(_ canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        backButton.alpha = canGoBack ? 1 : 0.3
        forwardButton.alpha = canGoForward ? 1 : 0.3
    }

    func setURLText(_ text: String) {
        guard !field.isFirstResponder else { return }
        field.text = text
    }

    func setFullBleed(_ on: Bool) {
        let name = on ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        fullBleedButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
    }

    // MARK: - Actions

    @objc private func noteInteraction() { onInteraction?() }
    @objc private func tapBack() { onInteraction?(); onBack?() }
    @objc private func tapForward() { onInteraction?(); onForward?() }
    @objc private func tapReload() { onInteraction?(); onReload?() }
    @objc private func tapHome() { onInteraction?(); onHome?() }
    @objc private func tapFullBleed() { onInteraction?(); onToggleFullBleed?() }

    // MARK: - Helpers

    private static func makeButton(_ systemName: String) -> UIButton {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        b.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.widthAnchor.constraint(equalToConstant: 38).isActive = true
        b.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return b
    }
}

// MARK: - UITextFieldDelegate

extension ControlBarView: UITextFieldDelegate {

    func textFieldDidBeginEditing(_ textField: UITextField) {
        onInteraction?()
        DispatchQueue.main.async { textField.selectAll(nil) }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return true }
        onSubmit?(text)
        return true
    }
}
