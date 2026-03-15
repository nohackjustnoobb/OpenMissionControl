// Borrowed from ejbills' DockDoor (GNU GPL v3.0):
// • AXUIElement: https://github.com/ejbills/DockDoor/blob/main/DockDoor/Extensions/AXUIElement.swift
// • PrivateApis: https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/PrivateApis.swift

import ApplicationServices

/// returns the CGWindowID of the provided AXUIElement
/// * macOS 10.10+
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: inout CGWindowID) -> AXError

enum AxError: Error {
    case runtimeError
}

extension AXUIElement {
    func axCallWhichCanThrow<T>(_ result: AXError, _ successValue: inout T) throws -> T? {
        switch result {
        case .success: return successValue
        // .cannotComplete can happen if the app is unresponsive; we throw in that case to retry until the call succeeds
        case .cannotComplete: throw AxError.runtimeError
        // for other errors it's pointless to retry
        default: return nil
        }
    }

    func attribute<T>(_ key: String, _ _: T.Type) throws -> T? {
        var value: AnyObject?
        return try axCallWhichCanThrow(AXUIElementCopyAttributeValue(self, key as CFString, &value), &value) as? T
    }

    private func value<T>(_ key: String, _ target: T, _ type: AXValueType) throws -> T? {
        if let a = try attribute(key, AXValue.self) {
            var value = target
            let success = withUnsafeMutablePointer(to: &value) { ptr in
                AXValueGetValue(a, type, ptr)
            }
            return success ? value : nil
        }
        return nil
    }

    func cgWindowId() throws -> CGWindowID? {
        var id = CGWindowID(0)
        return try axCallWhichCanThrow(_AXUIElementGetWindow(self, &id), &id)
    }

    func windows() throws -> [AXUIElement]? {
        return try attribute(kAXWindowsAttribute as String, [AXUIElement].self)
    }

    func performAction(_ action: String) throws {
        var unused: Void = ()
        try axCallWhichCanThrow(AXUIElementPerformAction(self, action as CFString), &unused)
    }
}
