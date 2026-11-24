import Foundation

/// 注入到 3x-ui 页面里的脚本。
enum InjectedScripts {
    /// 把钥匙串里的账号密码填进 3x-ui 的登录表单（Ant Design 的表单需要触发原生 setter 与 input 事件才会同步）。
    /// `__USER__` / `__PASSWORD__` 会被替换成 JSON 安全字符串字面量。
    static let fillLoginTemplate = #"""
    (function(){
      try {
        var user = __USER__;
        var pass = __PASSWORD__;
        function setValue(el, value) {
          if (!el) return false;
          try {
            var proto = Object.getPrototypeOf(el);
            var desc = Object.getOwnPropertyDescriptor(proto, 'value');
            if (desc && desc.set) { desc.set.call(el, value); } else { el.value = value; }
          } catch (e) { el.value = value; }
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }
        function pickUser() {
          var candidates = ['#username', 'input[name="username"]', 'input[autocomplete="username"]', 'input[name="user"]', 'input[type="text"]'];
          for (var i = 0; i < candidates.length; i++) {
            var el = document.querySelector(candidates[i]);
            if (el && el.offsetParent !== null) { return el; }
          }
          return document.querySelector('input[type="text"]');
        }
        var u = pickUser();
        var p = document.querySelector('input[type="password"]');
        var okUser = setValue(u, user);
        var okPass = setValue(p, pass);
        if (u && u.blur) { u.blur(); }
        if (p && p.blur) { p.blur(); }
        return JSON.stringify({ user: okUser, password: okPass });
      } catch (e) { return JSON.stringify({ error: String(e) }); }
    })();
    """#

    /// 在页面里搜集订阅链接与二维码（3x-ui 客户端列表里每行都有 QR 与 sub 链接）。
    static let extractLinks = #"""
    (function(){
      try {
        var links = [];
        var qrs = [];
        function push(list) {
          for (var i = 0; i < list.length; i++) {
            var v = list[i];
            if (!v) continue;
            v = String(v).trim();
            if (!v) continue;
            var isNode = /^(vmess|vless|trojan|ss|ssr|hysteria2?|tuic|wireguard):\/\//i.test(v);
            var isSub = v.indexOf('/sub/') >= 0 || /[?&]sub=/.test(v) || /subscription/i.test(v);
            if ((isNode || isSub) && links.indexOf(v) < 0) { links.push(v); }
          }
        }
        var anchors = document.querySelectorAll('a[href]');
        var hrefs = [];
        for (var i = 0; i < anchors.length; i++) { hrefs.push(anchors[i].href); }
        push(hrefs);

        var fields = document.querySelectorAll('input, textarea');
        var values = [];
        for (var j = 0; j < fields.length; j++) { values.push(fields[j].value); }
        push(values);

        var text = document.body ? (document.body.innerText || '') : '';
        var matched = text.match(/(vmess|vless|trojan|ss|ssr|hysteria2?|tuic):\/\/[^\s"'<>]+/gi) || [];
        push(matched);

        var images = document.querySelectorAll('img');
        for (var k = 0; k < images.length; k++) {
          var src = images[k].currentSrc || images[k].src;
          if (!src) continue;
          var big = (images[k].naturalWidth >= 100 && images[k].naturalHeight >= 100);
          if (src.indexOf('data:image') === 0 || /qrcode|qr-code|qr_/i.test(src) || big) {
            qrs.push({ src: src, width: images[k].naturalWidth || 0, height: images[k].naturalHeight || 0 });
          }
        }
        var canvases = document.querySelectorAll('canvas');
        for (var c = 0; c < canvases.length; c++) {
          try {
            if (canvases[c].width >= 100 && canvases[c].height >= 100) {
              qrs.push({ src: canvases[c].toDataURL('image/png'), width: canvases[c].width, height: canvases[c].height });
            }
          } catch (e) {}
        }
        return JSON.stringify({ links: links, qrs: qrs });
      } catch (e) { return JSON.stringify({ links: [], qrs: [], error: String(e) }); }
    })();
    """#

    /// 生成 fillLogin 脚本，账号密码都做 JSON 转义后再塞进去。
    static func fillLogin(user: String, password: String) -> String {
        let userLiteral = jsonLiteral(user)
        let passwordLiteral = jsonLiteral(password)
        return fillLoginTemplate
            .replacingOccurrences(of: "__USER__", with: userLiteral)
            .replacingOccurrences(of: "__PASSWORD__", with: passwordLiteral)
    }

    /// 把任意字符串变成合法的 JS/JSON 字符串字面量（含引号）。
    static func jsonLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let text = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // 形如 ["..."]，掐掉方括号只剩字面量。
        var trimmed = text
        if trimmed.hasPrefix("[") { trimmed.removeFirst() }
        if trimmed.hasSuffix("]") { trimmed.removeLast() }
        return trimmed
    }
}
