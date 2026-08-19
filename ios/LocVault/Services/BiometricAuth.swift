import Foundation
import LocalAuthentication

/// Thin wrapper around LocalAuthentication. Uses .deviceOwnerAuthentication
/// (Face ID/Touch ID with passcode fallback) rather than biometrics-only, so
/// a device without Face ID enrolled still has a way in via passcode.
enum BiometricAuth {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Device has neither biometrics nor a passcode set up at all —
            // there is nothing to gate with, so don't lock the user out.
            return true
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
