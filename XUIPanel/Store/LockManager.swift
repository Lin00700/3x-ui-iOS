import Foundation
import LocalAuthentication
import UIKit

/// 面容 ID / 设备密码锁。开启后每次冷启动与回到前台都会上锁。
final class LockManager: ObservableObject {
    @Published private(set) var isLocked: Bool = false
    @Published private(set) var isAuthenticating: Bool = false
    @Published var message: String?

    private var context: LAContext?

    /// 设备是否可以评估「面容/触控 ID + 密码」。
    var canUseDeviceAuth: Bool {
        var error: NSError?
        let probe = LAContext()
        return probe.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    var biometryName: String {
        let probe = LAContext()
        var error: NSError?
        guard probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "设备密码"
        }
        switch probe.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        default: return "设备密码"
        }
    }

    func lock() {
        isLocked = true
        message = nil
    }

    func unlockIfNeeded() {
        guard isLocked else { return }
        authenticate()
    }

    func authenticate() {
        guard !isAuthenticating else { return }
        guard isLocked else { return }

        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = "输入密码"
        self.context = context

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 设备没设密码：锁形同虚设，直接放行并说明原因，避免用户被关在门外。
            isLocked = false
            message = "此设备未设置面容 ID 或密码，隐私锁无法生效。"
            return
        }

        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁 3x-ui 面板与已保存的服务器") { [weak self] success, evaluationError in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAuthenticating = false
                if success {
                    self.isLocked = false
                    self.message = nil
                } else if let evaluationError = evaluationError {
                    self.message = (evaluationError as NSError).code == LAError.userCancel.rawValue
                        ? "已取消解锁"
                        : evaluationError.localizedDescription
                }
                self.context = nil
            }
        }
    }
}
