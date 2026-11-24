import SwiftUI
import WebKit

/// 把控制器里的 WKWebView 放进 SwiftUI。
struct PanelWebView: UIViewRepresentable {
    @ObservedObject var controller: PanelWebController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // WebView 由控制器持有，这里不需要做任何事。
    }
}
