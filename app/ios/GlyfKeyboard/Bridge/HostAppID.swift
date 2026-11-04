import UIKit
import os.log

/// The bundle id of the app the keyboard is typing in, so Glyf can send the
/// person back to it after opening for voice (VoiceLink.returnApp).
///
/// PRIVATE API. iOS has no public way for a keyboard to know its host app
/// (Apple DTS, developer.apple.com/forums/thread/826851, FB22247647). This
/// reads what UIKit and PlugInKit keep for themselves, the way KeyboardKit,
/// Wispr Flow and others did before iOS 26.4:
///
/// 1. `_hostBundleID` on the keyboard's parent view controller (KVC).
/// 2. `_hostPID` on the same controller, then PlugInKit's `PKService`
///    personalities for that pid, its NSXPCConnection's `_xpcConnection`, and
///    libxpc's `xpc_connection_copy_bundle_id` (looked up with dlsym).
///
/// Reports (2026-11): both answer nil on iOS 26.4 and later; through iOS
/// 26.3 the second one works, and the first one is nil on many versions.
/// Every step is checked before it is called (responds(to:), ivar lookups,
/// dlsym), so a missing piece gives nil, never a crash. All names are built
/// at run time; nothing private is linked.
///
/// App Review: Guideline 2.5.1 (only public APIs). Apple's scan looks for
/// private selectors and symbols; strings built at run time are not linked,
/// but a reviewer who finds them can reject the build. Turn it off with
/// `voiceReturn = false` in settings (the keyboard then sends no host id and
/// Glyf shows its "go back" line).
enum HostAppID {
    private static let log = Logger(subsystem: "so.glyf.keyboard", category: "voice")

    static func read(from vc: UIInputViewController) -> String? {
        if let id = viaHostBundleID(vc) { return id }
        if let id = viaXPC(vc) { return id }
        log.log("GLYF_VOICE host id unknown")
        return nil
    }

    /// A believable bundle id that is not the keyboard's own.
    private static func clean(_ raw: Any?) -> String? {
        guard let s = raw as? String else { return nil }
        let id = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != "<null>", id.contains("."),
              id != Bundle.main.bundleIdentifier, !id.hasPrefix("com.arpit.glyf")
        else { return nil }
        return id
    }

    // MARK: 1. _hostBundleID

    private static func viaHostBundleID(_ vc: UIInputViewController) -> String? {
        guard let parent = vc.parent else { return nil }
        let id = clean(value(parent, "_hostBundleID"))
        if let id { log.log("GLYF_VOICE host id via _hostBundleID \(id, privacy: .public)") }
        return id
    }

    // MARK: 2. _hostPID → PKService → xpc_connection_copy_bundle_id

    private typealias CopyBundleID = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar>?

    private static func viaXPC(_ vc: UIInputViewController) -> String? {
        guard let parent = vc.parent,
              let pid = (value(parent, "_hostPID") as? NSNumber)?.int32Value, pid > 0,
              let serviceClass = NSClassFromString("PKService") as? NSObject.Type
        else { return nil }
        let defaultSel = NSSelectorFromString("defaultService")
        guard serviceClass.responds(to: defaultSel),
              let service = serviceClass.perform(defaultSel)?.takeUnretainedValue() as? NSObject,
              let personalities = value(service, "personalities") as? [AnyHashable: Any]
        else { return nil }
        // Keyed by this extension's bundle id, then by the host's pid.
        let mine = Bundle.main.bundleIdentifier ?? ""
        let byPID = (personalities[mine] ?? personalities.values.first) as? [AnyHashable: Any]
        guard let byPID else { return nil }
        let personality = (byPID[NSNumber(value: pid)] ?? byPID[Int(pid)] ?? byPID[pid]
            ?? (byPID.count == 1 ? byPID.values.first : nil)) as? NSObject
        guard let personality,
              let connection = value(personality, "connection") as? NSObject,
              let xpcValue = value(connection, "_xpcConnection"),
              let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "xpc_connection_copy_bundle_id")
        else { return nil }
        let xpc = xpcValue as AnyObject
        let copy = unsafeBitCast(sym, to: CopyBundleID.self)
        guard let cString = copy(Unmanaged.passUnretained(xpc).toOpaque()) else { return nil }
        defer { free(cString) }
        let id = clean(String(cString: cString))
        if let id { log.log("GLYF_VOICE host id via xpc \(id, privacy: .public)") }
        return id
    }

    // MARK: Safe KVC

    /// `obj.value(forKey: key)` only when it can't throw: a method by that
    /// name, or an object-typed ivar (`key` or `_key`). An unknown key would
    /// raise NSUndefinedKeyException and take the keyboard down.
    private static func value(_ obj: NSObject, _ key: String) -> Any? {
        if obj.responds(to: NSSelectorFromString(key)) {
            return obj.value(forKey: key)
        }
        var cls: AnyClass? = type(of: obj)
        while let c = cls {
            if let ivar = class_getInstanceVariable(c, key) ?? class_getInstanceVariable(c, "_" + key) {
                guard let enc = ivar_getTypeEncoding(ivar), enc.pointee == CChar(UInt8(ascii: "@"))
                else { return nil }
                return object_getIvar(obj, ivar)
            }
            cls = class_getSuperclass(c)
        }
        return nil
    }
}
