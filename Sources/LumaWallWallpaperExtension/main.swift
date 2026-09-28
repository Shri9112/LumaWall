import AppKit
import Darwin
import ExtensionFoundation
import Foundation
import QuartzCore

private final class WallpaperXPCHandler: NSObject, WallpaperExtensionXPCProtocol {
    private var activeRenderers: [UInt32: ExtensionVideoRenderer] = [:]
    private var activeContexts: [UInt32: AnyObject] = [:]

    func acquire(withId id: Any?, request: Any?, reply: @escaping @Sendable (Any?, NSError?) -> Void) {
        ExtensionPreferences.shared.reload()
        guard let config = ExtensionPreferences.shared.config,
              FileManager.default.fileExists(atPath: config.videoPath) else {
            let error = NSError(domain: "com.lumawall.extension", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active video staged for LumaWall Lock Screen."])
            reply(nil, error)
            return
        }

        let videoURL = URL(fileURLWithPath: config.videoPath)
        let thumbURL = URL(fileURLWithPath: config.thumbnailPath)

        // 1. Create CoreAnimation Remote Context
        guard let contextClass = NSClassFromString("CAContext"),
              let rawContext = (contextClass as AnyObject).perform(NSSelectorFromString("remoteContext"))?.takeUnretainedValue() else {
            let error = NSError(domain: "com.lumawall.extension", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate CAContext."])
            reply(nil, error)
            return
        }

        let context = rawContext as AnyObject
        let contextIdValue = context.value(forKey: "contextId") as? UInt32 ?? 0
        guard contextIdValue != 0 else {
            let error = NSError(domain: "com.lumawall.extension", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid CAContext ID."])
            reply(nil, error)
            return
        }

        // 2. Build CALayer Hierarchy
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1664)
        let rootLayer = CALayer()
        rootLayer.frame = CGRect(origin: .zero, size: screenSize)
        rootLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        let renderer = ExtensionVideoRenderer(rootLayer: rootLayer, videoURL: videoURL, thumbnailURL: thumbURL)
        context.setValue(rootLayer, forKey: "layer")
        CATransaction.flush()

        activeRenderers[contextIdValue] = renderer
        activeContexts[contextIdValue] = context

        // 3. Wrap into WallpaperRemoteContextXPC
        guard let response = createRemoteContextXPC(contextId: contextIdValue) else {
            let error = NSError(domain: "com.lumawall.extension", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to construct WallpaperRemoteContextXPC."])
            reply(nil, error)
            return
        }

        reply(response, nil)
    }

    func update(withId id: Any?, request: Any?, reply: @escaping @Sendable (NSError?) -> Void) {
        reply(nil)
    }

    func invalidate(withId id: Any?, reply: @escaping @Sendable (NSError?) -> Void) {
        for (_, renderer) in activeRenderers {
            renderer.cleanup()
        }
        activeRenderers.removeAll()
        activeContexts.removeAll()
        reply(nil)
    }

    func snapshot(withId id: Any?, reply: @escaping @Sendable (Any?, NSError?) -> Void) {
        reply(nil, nil)
    }

    func provideSettingsViewModels(withContentTypes types: Any?, reply: @escaping @Sendable (Any?, NSError?) -> Void) {
        reply(nil, nil)
    }

    func selectedChoicesDidChange(for id: Any?, reply: @escaping @Sendable (NSError?) -> Void) {
        reply(nil)
    }

    func isChoiceDownloaded(with choiceID: Any?, reply: @escaping @Sendable (Bool, NSError?) -> Void) {
        reply(true, nil)
    }

    func handleNotification(withNamed name: Any?, reply: @escaping @Sendable (NSError?) -> Void) {
        reply(nil)
    }
}

private struct LumaWallWallpaperConfiguration: AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool {
        let exported = NSXPCInterface(with: WallpaperExtensionXPCProtocol.self)
        let proxy = NSXPCInterface(with: WallpaperExtensionProxyXPCProtocol.self)

        let runtimeNames = [
            "WallpaperUpdateRequestXPC",
            "WallpaperRemoteContextXPC",
            "WallpaperSnapshotXPC",
            "WallpaperContentTypeSetXPC",
            "WallpaperSettingsViewModelsXPC"
        ]
        let allowed = NSMutableSet(array: [
            NSString.self, NSNumber.self, NSData.self, NSArray.self,
            NSDictionary.self, NSURL.self, NSError.self
        ])
        for name in runtimeNames {
            if let cls = objc_getClass(name) { allowed.add(cls) }
        }
        let classes = allowed as! Set<AnyHashable>

        let acquire = #selector(WallpaperExtensionXPCProtocol.acquire(withId:request:reply:))
        exported.setClasses(classes, for: acquire, argumentIndex: 0, ofReply: false)
        exported.setClasses(classes, for: acquire, argumentIndex: 1, ofReply: false)
        exported.setClasses(classes, for: acquire, argumentIndex: 0, ofReply: true)

        let update = #selector(WallpaperExtensionXPCProtocol.update(withId:request:reply:))
        exported.setClasses(classes, for: update, argumentIndex: 0, ofReply: false)
        exported.setClasses(classes, for: update, argumentIndex: 1, ofReply: false)

        connection.exportedInterface = exported
        connection.remoteObjectInterface = proxy
        connection.exportedObject = WallpaperXPCHandler()
        connection.resume()
        return true
    }
}

@main
private final class LumaWallWallpaperExtension: NSObject, AppExtension {
    override required init() {
        super.init()
        let path = "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"
        _ = dlopen(path, RTLD_LAZY)
    }

    var configuration: some AppExtensionConfiguration {
        LumaWallWallpaperConfiguration()
    }
}
