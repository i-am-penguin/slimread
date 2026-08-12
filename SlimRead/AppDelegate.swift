import UIKit
import BackgroundTasks

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    /// Must match the BGTaskSchedulerPermittedIdentifiers entry in Info.plist. iOS
    /// refuses to register a task whose identifier is not declared there.
    static let refreshTaskID = "com.example.slimread.tweaks-refresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Registration has to happen before the app finishes launching, every launch,
        // whether or not a task is ever scheduled.
        registerTweaksRefresh()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = .black
        window.rootViewController = BrowserViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleTweaksRefresh()
    }

    // MARK: - Background tweaks refresh
    //
    // Pulls tweaks/ while the app is not in use, so the newest copy is already stored
    // by the time it is opened.
    //
    // Without this the fetch starts at launch and races the first page load. The page
    // wins, so it renders with the previous copy, and BrowserViewController has to
    // reload once the new script arrives - correct, but visible. Landing the files
    // ahead of time means the user script is registered from the newest copy at web
    // view creation and there is nothing to correct.
    //
    // Strictly an optimisation: iOS decides if and when these run, and the user can
    // turn Background App Refresh off entirely, so the reload path stays as it is.

    private func registerTweaksRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskID,
            using: nil
        ) { task in
            self.handleTweaksRefresh(task)
        }
    }

    private func scheduleTweaksRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        // A floor, not a promise - iOS schedules these on its own judgement.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleTweaksRefresh(_ task: BGTask) {
        // Queue the next one straight away: a task that does not reschedule itself
        // runs exactly once, ever.
        scheduleTweaksRefresh()

        var finished = false
        func complete(_ success: Bool) {
            guard !finished else { return }   // expiration and completion can race
            finished = true
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = { complete(false) }

        TweaksLoader.refresh { update in
            // Nothing to do with the result here - refresh has already stored it, and
            // the next launch reads it through TweaksLoader.cached.
            complete(update != nil)
        }
    }
}
