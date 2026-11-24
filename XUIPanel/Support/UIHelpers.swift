import Foundation
import UIKit

/// 从任意视图里找到最上层的控制器 / 窗口，用来弹系统面板（分享、选择文件、JS 弹窗）。
enum UIHelpers {
    static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
        var fallback: UIWindow?
        for case let scene as UIWindowScene in scenes {
            let windows = scene.windows
            if let key = windows.first(where: { $0.isKeyWindow }) {
                if scene.activationState == .foregroundActive { return key }
                if fallback == nil { fallback = key }
            } else if fallback == nil {
                fallback = windows.first
            }
        }
        return fallback
    }

    static func topViewController() -> UIViewController? {
        var controller = keyWindow()?.rootViewController
        while let presented = controller?.presentedViewController {
            if let navigation = presented as? UINavigationController {
                controller = navigation.visibleViewController ?? navigation
            } else if let tab = presented as? UITabBarController {
                controller = tab.selectedViewController ?? tab
            } else {
                controller = presented
            }
        }
        if let navigation = controller as? UINavigationController {
            return navigation.visibleViewController ?? navigation
        }
        if let tab = controller as? UITabBarController {
            return tab.selectedViewController ?? tab
        }
        return controller
    }

    static func present(_ controller: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let top = topViewController() else { return }
            if top.presentedViewController != nil {
                top.dismiss(animated: false) {
                    topViewController()?.present(controller, animated: animated, completion: completion)
                }
                return
            }
            top.present(controller, animated: animated, completion: completion)
        }
    }

    static func share(items: [Any], sourceView: UIView? = nil) {
        guard !items.isEmpty else { return }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            let anchor = sourceView ?? topViewController()?.view
            popover.sourceView = anchor
            popover.sourceRect = CGRect(x: (anchor?.bounds.midX ?? 0), y: (anchor?.bounds.midY ?? 0), width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(activity)
    }

    static func copyToPasteboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// 把 data URL 或远程图片读成 UIImage（二维码分享用）。
    static func loadImage(from source: String, completion: @escaping (UIImage?) -> Void) {
        if let inline = loadImageSync(from: source) {
            completion(inline)
            return
        }
        guard let url = URL(string: source), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    /// 同步解析 data URL（页面里内联的二维码基本都是这种），远程图片返回 nil。
    static func loadImageSync(from source: String) -> UIImage? {
        guard source.hasPrefix("data:image"), let comma = source.firstIndex(of: ",") else { return nil }
        let base64 = String(source[source.index(after: comma)...])
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }
}
