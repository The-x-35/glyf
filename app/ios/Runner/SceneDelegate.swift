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
      route(url, scene: scene)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if let url = URLContexts.first?.url {
      route(url, scene: scene)
    }
  }

  /// glyf://voice is the keyboard's mic: native, so listening starts before
  /// Flutter has drawn a frame. Everything else is Flutter's.
  private func route(_ url: URL, scene: UIScene) {
    if url.scheme == "glyf", url.host == "voice" {
      VoiceHost.shared.open(url, scene: scene as? UIWindowScene)
      return
    }
    GlyfBridge.shared.handleDeepLink(url)
  }
}
