import UIKit
import WebKit

/// A single full-screen WKWebView with no permanent chrome.
///
/// The whole point of this app: `prefersStatusBarHidden` returns `true` unconditionally,
/// so the status bar is gone in portrait as well as landscape. No orientation trickery,
/// no private API — this is the documented, App Store-legal way to do it.
final class BrowserViewController: UIViewController {

    // MARK: - Config

    private enum Key {
        static let lastURL = "SlimRead.lastURL"
        static let fullBleed = "SlimRead.fullBleed"
    }

    /// Change this if you want the app to open somewhere other than Tapas.
    private let homeURL = URL(string: "https://tapas.io")!

    /// Seconds of inactivity before the control bar auto-hides again.
    private let autoHideDelay: TimeInterval = 5

    // MARK: - Views

    private var webView: WKWebView!
    private let controls = ControlBarView()
    private let handle = UIView()
    private let progress = UIProgressView(progressViewStyle: .bar)

    // MARK: - State

    private var controlsVisible = false
    private var hideWorkItem: DispatchWorkItem?
    private var observations: [NSKeyValueObservation] = []
    private var keyboardOverlap: CGFloat = 0

    private var controlsBottom: NSLayoutConstraint!
    private var webTop: NSLayoutConstraint!
    private var webBottom: NSLayoutConstraint!

    /// When true the web view ignores the safe area entirely and paints under the
    /// Dynamic Island / notch and home indicator. When false it sits inside the safe area.
    private var fullBleed: Bool {
        didSet {
            UserDefaults.standard.set(fullBleed, forKey: Key.fullBleed)
            applyLayoutMode()
            controls.setFullBleed(fullBleed)
        }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.fullBleed) == nil {
            defaults.set(true, forKey: Key.fullBleed)
        }
        fullBleed = defaults.bool(forKey: Key.fullBleed)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - System UI overrides
    //
    // These four are the entire trick. Info.plist sets UIViewControllerBasedStatusBarAppearance
    // to YES so these win, and UIStatusBarHidden to YES so the launch screen matches.

    override var prefersStatusBarHidden: Bool { true }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// Stops an upward swipe near the bottom edge from yanking you out of the app
    /// mid-scroll. First swipe reveals the indicator, second one actually leaves.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        buildWebView()
        buildOverlay()
        buildGestures()
        observeWebView()
        observeKeyboard()

        applyLayoutMode()
        controls.setFullBleed(fullBleed)

        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()

        load(restoredURL() ?? homeURL)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Build

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()          // persistent cookies, so Tapas stays logged in
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        view.addSubview(webView)

        webTop = webView.topAnchor.constraint(equalTo: view.topAnchor)
        webBottom = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webTop,
            webBottom
        ])
    }

    private func buildOverlay() {
        // Thin loading hairline where the status bar used to live.
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .white
        progress.trackTintColor = .clear
        progress.alpha = 0
        view.addSubview(progress)

        // Always-visible grab handle: a small pill at the bottom centre. It swallows its own
        // taps so it never fights with links on the page.
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.backgroundColor = .clear
        view.addSubview(handle)

        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        pill.layer.cornerRadius = 2
        pill.isUserInteractionEnabled = false
        handle.addSubview(pill)

        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        controlsBottom = controls.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 240)

        NSLayoutConstraint.activate([
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),

            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            handle.widthAnchor.constraint(equalToConstant: 120),
            handle.heightAnchor.constraint(equalToConstant: 34),

            pill.centerXAnchor.constraint(equalTo: handle.centerXAnchor),
            pill.centerYAnchor.constraint(equalTo: handle.centerYAnchor, constant: -2),
            pill.widthAnchor.constraint(equalToConstant: 40),
            pill.heightAnchor.constraint(equalToConstant: 4),

            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsBottom
        ])

        wireControls()
    }

    private func wireControls() {
        controls.onBack = { [weak self] in self?.webView.goBack() }
        controls.onForward = { [weak self] in self?.webView.goForward() }
        controls.onReload = { [weak self] in self?.webView.reload() }
        controls.onHome = { [weak self] in
            guard let self else { return }
            self.load(self.homeURL)
        }
        controls.onToggleFullBleed = { [weak self] in
            guard let self else { return }
            self.fullBleed.toggle()
        }
        controls.onSubmit = { [weak self] text in
            guard let self, let url = Self.resolve(text) else { return }
            self.load(url)
            self.setControls(visible: false)
        }
        controls.onInteraction = { [weak self] in self?.scheduleAutoHide() }
    }

    private func buildGestures() {
        let handleTap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        handle.addGestureRecognizer(handleTap)

        // Two-finger tap anywhere is the escape hatch if the pill is awkward to reach.
        let twoFinger = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        twoFinger.numberOfTouchesRequired = 2
        twoFinger.delegate = self
        view.addGestureRecognizer(twoFinger)
    }

    // MARK: - Layout modes

    private func applyLayoutMode() {
        webTop.isActive = false
        webBottom.isActive = false

        if fullBleed {
            webTop = webView.topAnchor.constraint(equalTo: view.topAnchor)
            webBottom = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        } else {
            webTop = webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            webBottom = webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        }

        webTop.isActive = true
        webBottom.isActive = true

        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    // MARK: - Controls show / hide

    @objc private func toggleControls() {
        setControls(visible: !controlsVisible)
    }

    private func setControls(visible: Bool) {
        controlsVisible = visible
        if !visible { controls.field.resignFirstResponder() }

        controlsBottom.constant = visible ? -keyboardOverlap : 240

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.handle.alpha = visible ? 0 : 1
            self.view.layoutIfNeeded()
        }

        if visible { scheduleAutoHide() } else { hideWorkItem?.cancel() }
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.controls.field.isFirstResponder else { return }
            self.setControls(visible: false)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: work)
    }

    // MARK: - Keyboard

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveState),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func keyboardFrameChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        keyboardOverlap = max(0, view.bounds.maxY - converted.minY)
        if controlsVisible {
            controlsBottom.constant = -keyboardOverlap
            UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
        }
    }

    @objc private func keyboardWillHide() {
        keyboardOverlap = 0
        if controlsVisible {
            controlsBottom.constant = 0
            UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
            scheduleAutoHide()
        }
    }

    // MARK: - Navigation

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Turns whatever the user typed into a URL: bare hosts get https://, anything
    /// with a space or no dot becomes a DuckDuckGo search.
    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }

        let looksLikeHost = !trimmed.contains(" ") && trimmed.contains(".")
        if looksLikeHost, let url = URL(string: "https://" + trimmed) {
            return url
        }

        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }

    private func restoredURL() -> URL? {
        guard let string = UserDefaults.standard.string(forKey: Key.lastURL) else { return nil }
        return URL(string: string)
    }

    @objc private func saveState() {
        if let url = webView.url, url.scheme?.hasPrefix("http") == true {
            UserDefaults.standard.set(url.absoluteString, forKey: Key.lastURL)
        }
    }

    // MARK: - KVO

    private func observeWebView() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                self?.progress.setProgress(Float(webView.estimatedProgress), animated: true)
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                guard let self else { return }
                if webView.isLoading {
                    self.progress.setProgress(0, animated: false)
                    UIView.animate(withDuration: 0.15) { self.progress.alpha = 1 }
                } else {
                    UIView.animate(withDuration: 0.3, delay: 0.15) {
                        self.progress.alpha = 0
                    } completion: { _ in
                        self.progress.setProgress(0, animated: false)
                    }
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                self?.controls.setURLText(webView.url?.absoluteString ?? "")
                self?.saveState()
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                self?.controls.setCanGoBack(webView.canGoBack, canGoForward: webView.canGoForward)
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                self?.controls.setCanGoBack(webView.canGoBack, canGoForward: webView.canGoForward)
            }
        ]
    }
}

// MARK: - WKNavigationDelegate

extension BrowserViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Hand tel:, mailto:, itms-apps: etc. to the system instead of failing to load them.
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https", scheme != "about" {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        saveState()
    }
}

// MARK: - WKUIDelegate

extension BrowserViewController: WKUIDelegate {

    /// target="_blank" links would otherwise silently do nothing; load them in place.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            load(url)
        }
        return nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension BrowserViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
