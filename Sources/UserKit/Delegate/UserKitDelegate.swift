import Foundation

public protocol UserKitDelegate: AnyObject {
    @MainActor func handleLog(
        level: String,
        scope: String,
        message: String?,
        info: [String: Any]?,
        error: Error?
    )
}

extension UserKitDelegate {
    @MainActor public func handleLog(
        level: String,
        scope: String,
        message: String?,
        info: [String: Any]?,
        error: Error?
    ) {}
}
