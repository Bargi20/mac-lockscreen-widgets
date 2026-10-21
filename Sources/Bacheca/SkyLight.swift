import AppKit

/// Moves windows into a private WindowServer space that sits above the lock screen.
///
/// Uses undocumented SkyLight functions, loaded at runtime so a missing symbol
/// disables the feature instead of crashing. Technique from SkyLightWindow
/// by Lakr Aream (MIT): https://github.com/Lakr233/SkyLightWindow
final class SkyLight {
    static let shared = SkyLight()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock: above the lock screen (300).
    private static let lockScreenLevel: Int32 = 400

    private let connection: Int32
    private let space: Int32
    private let addWindows: SpaceAddWindowsAndRemoveFromSpaces

    private init?() {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
            let pMain = dlsym(handle, "SLSMainConnectionID"),
            let pCreate = dlsym(handle, "SLSSpaceCreate"),
            let pLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let pShow = dlsym(handle, "SLSShowSpaces"),
            let pAdd = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }

        let mainConnection = unsafeBitCast(pMain, to: MainConnectionID.self)
        let create = unsafeBitCast(pCreate, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(pLevel, to: SpaceSetAbsoluteLevel.self)
        let show = unsafeBitCast(pShow, to: ShowSpaces.self)
        addWindows = unsafeBitCast(pAdd, to: SpaceAddWindowsAndRemoveFromSpaces.self)

        connection = mainConnection()
        space = create(connection, 1, 0)
        guard space != 0 else { return nil }
        _ = setLevel(connection, space, Self.lockScreenLevel)
        _ = show(connection, [space] as CFArray)
    }

    func adopt(_ window: NSWindow) {
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}

/// True while the login window is covering the session.
func isScreenLocked() -> Bool {
    guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
}
