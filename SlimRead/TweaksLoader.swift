import Foundation

/// Fetches page-level CSS and JS from the repository at launch.
///
/// This is what makes "edit the repo, reopen the app, change is live" work. Anything
/// expressible as CSS or JS against the page - layout fixes, hiding site chrome, image
/// loading behaviour - lives in `tweaks/` on GitHub and needs no rebuild, no re-signing
/// and no reinstall. Only changes to native behaviour require a new build.
enum TweaksLoader {

    struct Tweaks {
        var css: String
        var js: String
    }

    /// Change this if you fork or rename the repository.
    static let baseURL = "https://raw.githubusercontent.com/i-am-penguin/slimread/main/tweaks/"

    private enum Key {
        static let css = "SlimRead.tweaks.css"
        static let js = "SlimRead.tweaks.js"
        static let stamp = "SlimRead.tweaks.updatedAt"
    }

    /// Last known good tweaks, or the built-in fallback on a fresh install with no network.
    static var cached: Tweaks {
        let defaults = UserDefaults.standard
        return Tweaks(
            css: defaults.string(forKey: Key.css) ?? Fallback.css,
            js:  defaults.string(forKey: Key.js)  ?? Fallback.js
        )
    }

    static var lastUpdated: Date? {
        UserDefaults.standard.object(forKey: Key.stamp) as? Date
    }

    struct Update {
        var tweaks: Tweaks
        var cssChanged: Bool
        /// The caller has to treat this differently: a stylesheet can be swapped into
        /// a live page, but a user script only takes effect at the next page load.
        var jsChanged: Bool
    }

    /// Pulls both files. Calls back only if something actually changed, and says which,
    /// so the caller can avoid a pointless reload.
    static func refresh(completion: @escaping (Update?) -> Void) {
        var fetchedCSS: String?
        var fetchedJS: String?
        let group = DispatchGroup()

        func fetch(_ name: String, into store: @escaping (String) -> Void) {
            // reloadIgnoringLocalCacheData skips the local store only. The remaining
            // delay is raw.githubusercontent.com's own edge cache (max-age=300), and
            // it cannot be defeated from here: a unique query parameter still comes
            // back X-Cache: HIT with the same Source-Age, because Fastly strips the
            // query for this origin. So a push can take up to five minutes to become
            // visible. Not worth working around - the fix that mattered was applying
            // a changed script without waiting for a navigation.
            guard let url = URL(string: baseURL + name) else { return }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8
            group.enter()
            URLSession.shared.dataTask(with: request) { data, response, _ in
                defer { group.leave() }
                guard
                    let data,
                    let http = response as? HTTPURLResponse, http.statusCode == 200,
                    let text = String(data: data, encoding: .utf8),
                    !text.isEmpty
                else { return }
                store(text)
            }.resume()
        }

        fetch("tweaks.css") { fetchedCSS = $0 }
        fetch("tweaks.js")  { fetchedJS  = $0 }

        group.notify(queue: .main) {
            let defaults = UserDefaults.standard
            var cssChanged = false
            var jsChanged = false

            if let fetchedCSS, fetchedCSS != defaults.string(forKey: Key.css) {
                defaults.set(fetchedCSS, forKey: Key.css)
                cssChanged = true
            }
            if let fetchedJS, fetchedJS != defaults.string(forKey: Key.js) {
                defaults.set(fetchedJS, forKey: Key.js)
                jsChanged = true
            }

            guard cssChanged || jsChanged else {
                completion(nil)
                return
            }

            defaults.set(Date(), forKey: Key.stamp)
            completion(Update(tweaks: cached, cssChanged: cssChanged, jsChanged: jsChanged))
        }
    }

    /// Wraps the CSS in a script that installs it as a <style> element. Done in JS rather
    /// than a stylesheet so it can also be swapped at runtime without a page reload.
    static func cssInstallScript(_ css: String) -> String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return """
        (function () {
            var id = 'slimread-tweaks';
            var style = document.getElementById(id);
            if (!style) {
                style = document.createElement('style');
                style.id = id;
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = `\(escaped)`;
        })();
        """
    }

    // MARK: - Offline fallback
    //
    // Only used on a fresh install with no network. The live copies in tweaks/ take over
    // as soon as the app can reach GitHub.

    enum Fallback {
        /// Deliberately does NOT force a black background.
        ///
        /// It used to, and that is the cover-thumbnail bug in miniature: sites with a
        /// light background and transparent cards turn every bit of grid spacing into a
        /// thick black border. Black belongs to the reader, and the reader is only
        /// identifiable from tweaks.js - which this fallback stands in for. So the safe
        /// thing to do with no network is almost nothing.
        static let css = """
        img { max-width: 100% !important; height: auto !important; }
        """

        static let js = ""
    }
}
