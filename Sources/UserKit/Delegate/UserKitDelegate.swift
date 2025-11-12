import Foundation

@MainActor
public protocol UserKitDelegate: AnyObject {
    func handleLog(
        level: String,
        scope: String,
        message: String?,
        info: [String: Any]?,
        error: Error?
    )
}

extension UserKitDelegate {
    public func handleLog(
        level: String,
        scope: String,
        message: String?,
        info: [String: Any]?,
        error: Error?
    ) {}
}
