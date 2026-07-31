import SwiftUI

@main
struct SlimReadApp: App {

    var body: some Scene {
        WindowGroup {
            BrowserContainer()
                .ignoresSafeArea(.all)
                .statusBarHidden(true)            // portrait included
                .persistentSystemOverlays(.hidden) // dims the home indicator
                .preferredColorScheme(.dark)
        }
    }
}

/// Bridges the UIKit browser into SwiftUI. All the real work lives in
/// BrowserViewController, which is byte-identical to the Xcode-project version.
struct BrowserContainer: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> BrowserViewController {
        BrowserViewController()
    }

    func updateUIViewController(_ uiViewController: BrowserViewController, context: Context) {}
}
