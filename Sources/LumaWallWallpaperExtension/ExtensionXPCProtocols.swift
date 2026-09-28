import Foundation
import ObjectiveC

@objc(LumaWallExtensionProxyXPCProtocol)
public protocol WallpaperExtensionProxyXPCProtocol {
    @objc(pingWithId:)
    func ping(withId id: Any?)

    @objc(updateSettingsViewModels:reply:)
    func updateSettingsViewModels(_ models: Any?, reply: @escaping (NSError?) -> Void)

    @objc(requestReadOnlyAccessTo:reply:)
    func requestReadOnlyAccess(to url: Any?, reply: @escaping (Any?) -> Void)

    @objc(invalidateSnapshotsWithReply:)
    func invalidateSnapshots(reply: @escaping (NSError?) -> Void)
}

@objc(LumaWallExtensionXPCProtocol)
public protocol WallpaperExtensionXPCProtocol {
    @objc(acquireWithId:request:reply:)
    func acquire(withId id: Any?, request: Any?, reply: @escaping @Sendable (Any?, NSError?) -> Void)

    @objc(updateWithId:request:reply:)
    func update(withId id: Any?, request: Any?, reply: @escaping @Sendable (NSError?) -> Void)

    @objc(invalidateWithId:reply:)
    func invalidate(withId id: Any?, reply: @escaping @Sendable (NSError?) -> Void)

    @objc(snapshotWithId:reply:)
    func snapshot(withId id: Any?, reply: @escaping @Sendable (Any?, NSError?) -> Void)

    @objc(provideSettingsViewModelsWithContentTypes:reply:)
    func provideSettingsViewModels(
        withContentTypes types: Any?,
        reply: @escaping @Sendable (Any?, NSError?) -> Void
    )

    @objc(selectedChoicesDidChangeFor:reply:)
    func selectedChoicesDidChange(for id: Any?, reply: @escaping @Sendable (NSError?) -> Void)

    @objc(isChoiceDownloadedWith:reply:)
    func isChoiceDownloaded(with choiceID: Any?, reply: @escaping @Sendable (Bool, NSError?) -> Void)

    @objc(handleNotificationWithNamed:reply:)
    func handleNotification(withNamed name: Any?, reply: @escaping @Sendable (NSError?) -> Void)
}

/// Wraps a CoreAnimation contextId into macOS WallpaperAgent's expected WallpaperRemoteContextXPC container.
public func createRemoteContextXPC(contextId: UInt32) -> AnyObject? {
    guard let runtimeClass = objc_getClass("WallpaperRemoteContextXPC") as? AnyClass,
          let instance = class_createInstance(runtimeClass, 0) else {
        return nil
    }

    let offset = class_getInstanceVariable(runtimeClass, "box").map(ivar_getOffset) ?? 8
    let instanceSize = class_getInstanceSize(runtimeClass)
    guard offset >= 0, offset + MemoryLayout<UInt32>.size <= instanceSize else {
        return nil
    }

    let object = instance as AnyObject
    Unmanaged.passUnretained(object).toOpaque()
        .advanced(by: offset)
        .storeBytes(of: contextId, as: UInt32.self)
    return object
}
