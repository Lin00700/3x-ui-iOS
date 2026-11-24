import Foundation
import WebKit

/// 网页端 User-Agent 常量。
enum UserAgent {
    /// 桌面 Safari（Mac）。3x-ui 的 Ant Design 表格在宽屏下才完整展开。
    static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static func string(for mode: UserAgentMode) -> String? {
        switch mode {
        case .desktop: return desktop
        case .mobile: return nil   // nil = 使用 WKWebView 默认的移动端 UA
        }
    }
}

/// 展示给工具栏的简短 UA 提示。
enum ViewportMode {
    /// 电脑版：把布局宽度当成 1280，然后缩放到屏幕宽度，表格不会被挤成一条。
    static let desktopJS = """
    (function(){
      try {
        var content = 'width=1280, initial-scale=0.30, minimum-scale=0.15, maximum-scale=4.0, user-scalable=yes';
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.setAttribute('name', 'viewport');
          (document.head || document.documentElement).appendChild(meta);
        }
        meta.setAttribute('content', content);
        document.documentElement.style.webkitTextSizeAdjust = '100%';
        return 'ok';
      } catch (e) { return 'error: ' + e; }
    })();
    """

    /// 手机版：交给 3x-ui 自己的响应式布局。
    static let mobileJS = """
    (function(){
      try {
        var content = 'width=device-width, initial-scale=1.0, maximum-scale=4.0, user-scalable=yes';
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.setAttribute('name', 'viewport');
          (document.head || document.documentElement).appendChild(meta);
        }
        meta.setAttribute('content', content);
        return 'ok';
      } catch (e) { return 'error: ' + e; }
    })();
    """
}
