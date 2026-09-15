import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // glyf:// deep links (SPEC §4: glyf://intent?id=<uuid>) arrive through the
  // scene lifecycle, not AppDelegate, under the scene-based Flutter template.

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url {
      GlyfBridge.shared.handleDeepLink(url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if let url = URLContexts.first?.url {
      GlyfBridge.shared.handleDeepLink(url)
    }
  }
}
