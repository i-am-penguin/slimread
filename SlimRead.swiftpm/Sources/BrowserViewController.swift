import UIKit
import WebKit

/// A single full-screen WKWebView with no permanent chrome.
///
/// The status bar is hidden in every orientation via `prefersStatusBarHidden`. Page-level
/// behaviour (layout fixes, image loading, hiding site chrome) is driven by CSS and JS
/// fetched from the repository at launch - see TweaksLoader.
final class BrowserViewController: UIViewController {

    // MARK: - Config

    private enum Key {
        static let lastURL = "SlimRead.lastURL"
        static let fullBleed = "SlimRead.fullBleed"
        static let seenGuide = "SlimRead.seenGuide"
    }

    /// Change this to open somewhere other than Tapas.
    private let homeURL = URL(string: "https://tapas.io")!

    /// Seconds of inactivity before the control bar hides itself.
    private let autoHideDelay: TimeInterval = 6

    /// Height of the invisible tap target at the top of the screen that toggles the bar.
    private let topTapZoneHeight: CGFloat = 64

    // MARK: - Views

    private var webView: WKWebView!
    private let controls = ControlBarView()
    private let topTapZone = UIView()
    private let progress = UIProgressView(progressViewStyle: .bar)

    // MARK: - State

    private var controlsVisible = false
    private var hideWorkItem: DispatchWorkItem?
    private var observations: [NSKeyValueObservation] = []
    private var keyboardOverlap: CGFloat = 0
    private var lastScrollOffset: CGFloat = 0

    private var controlsTop: NSLayoutConstraint!
    private var webTop: NSLayoutConstraint!
    private var webBottom: NSLayoutConstraint!

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

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        enlargeURLCache()

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
        refreshTweaks()

        if !UserDefaults.standard.bool(forKey: Key.seenGuide) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showGuide(firstRun: true)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyCornerRadius()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Performance

    /// WKWebView shares URLCache. The default disk allowance is small for a page that is
    /// mostly large images, so re-reading a chapter refetches everything.
    private func enlargeURLCache() {
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "slimread-cache"
        )
    }

    // MARK: - Build

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.suppressesIncrementalRendering = false
        config.userContentController = makeUserContentController()

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
        webView.scrollView.decelerationRate = .normal
        webView.layer.cornerCurve = .continuous
        webView.layer.masksToBounds = true
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

    private func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        let tweaks = TweaksLoader.cached

        // CSS first, at document start, so the page never flashes un-styled.
        controller.addUserScript(WKUserScript(
            source: TweaksLoader.cssInstallScript(tweaks.css),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        if !tweaks.js.isEmpty {
            controller.addUserScript(WKUserScript(
                source: tweaks.js,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }

        return controller
    }

    private func buildOverlay() {
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .white
        progress.trackTintColor = .clear
        progress.alpha = 0
        view.addSubview(progress)

        // Invisible strip across the top - the notch / Dynamic Island sits inside it.
        topTapZone.translatesAutoresizingMaskIntoConstraints = false
        topTapZone.backgroundColor = .clear
        view.addSubview(topTapZone)

        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        controlsTop = controls.topAnchor.constraint(equalTo: view.topAnchor, constant: -260)

        NSLayoutConstraint.activate([
            topTapZone.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topTapZone.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topTapZone.topAnchor.constraint(equalTo: view.topAnchor),
            topTapZone.heightAnchor.constraint(equalToConstant: topTapZoneHeight),

            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsTop,

            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2)
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
        controls.onToggleFullBleed = { [weak self] in self?.fullBleed.toggle() }
        controls.onGuide = { [weak self] in
            self?.setControls(visible: false)
            self?.showGuide(firstRun: false)
        }
        controls.onSubmit = { [weak self] text in
            guard let self, let url = Self.resolve(text) else { return }
            self.load(url)
            self.setControls(visible: false)
        }
        controls.onInteraction = { [weak self] in self?.scheduleAutoHide() }
    }

    private func buildGestures() {
        let topTap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        topTapZone.addGestureRecognizer(topTap)

        let twoFinger = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        twoFinger.numberOfTouchesRequired = 2
        twoFinger.delegate = self
        view.addGestureRecognizer(twoFinger)
    }

    // MARK: - Corner radius
    //
    // Squares off against rounded display corners otherwise. UIScreen knows the real
    // radius but only privately, so fall back to a sensible value per device shape.

    private func applyCornerRadius() {
        let radius: CGFloat
        if let known = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat, known > 0 {
            radius = known
        } else {
            radius = view.safeAreaInsets.top > 24 ? 47 : 0
        }
        webView.layer.cornerRadius = fullBleed ? radius : 0
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

        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
            self.applyCornerRadius()
        }
    }

    // MARK: - Controls show / hide

    @objc private func toggleControls() {
        setControls(visible: !controlsVisible)
    }

    private func setControls(visible: Bool) {
        controlsVisible = visible
        if !visible { controls.field.resignFirstResponder() }

        controlsTop.constant = visible ? 0 : -260

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
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

    // MARK: - Guide

    private func showGuide(firstRun: Bool) {
        let guide = GuideOverlayView()
        guide.onDismiss = { [weak guide] in
            UserDefaults.standard.set(true, forKey: Key.seenGuide)
            guide?.dismiss()
        }
        guide.present(in: view)
    }

    // MARK: - Keyboard

    private func observeKeyboard() {
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(keyboardFrameChanged(_:)),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        centre.addObserver(self, selector: #selector(keyboardWillHide),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
        centre.addObserver(self, selector: #selector(saveState),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        centre.addObserver(self, selector: #selector(appBecameActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func keyboardFrameChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        keyboardOverlap = max(0, view.bounds.maxY - converted.minY)
    }

    @objc private func keyboardWillHide() {
        keyboardOverlap = 0
        if controlsVisible { scheduleAutoHide() }
    }

    /// Pick up repo edits without needing the app to be reinstalled.
    @objc private func appBecameActive() {
        refreshTweaks()
    }

    // MARK: - Tweaks

    private func refreshTweaks() {
        TweaksLoader.refresh { [weak self] updated in
            guard let self, let updated else { return }

            // Swap the stylesheet live, then re-register scripts so the next page load
            // gets them at document start too.
            self.webView.evaluateJavaScript(TweaksLoader.cssInstallScript(updated.css))
            if !updated.js.isEmpty {
                self.webView.evaluateJavaScript(updated.js)
            }

            let controller = self.webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(
                source: TweaksLoader.cssInstallScript(updated.css),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
            if !updated.js.isEmpty {
                controller.addUserScript(WKUserScript(
                    source: updated.js,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                ))
            }
        }
    }

    // MARK: - Navigation

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

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
            },
            // Hide the bar as soon as the reader scrolls down. KVO rather than a scroll
            // delegate, because WKWebView owns its scroll view's delegate.
            webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                guard let self else { return }
                let offset = scrollView.contentOffset.y
                defer { self.lastScrollOffset = offset }
                guard self.controlsVisible, !self.controls.field.isFirstResponder else { return }
                if offset - self.lastScrollOffset > 6 {
                    self.setControls(visible: false)
                }
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
        lastScrollOffset = webView.scrollView.contentOffset.y
    }
}

// MARK: - WKUIDelegate

extension BrowserViewController: WKUIDelegate {

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
