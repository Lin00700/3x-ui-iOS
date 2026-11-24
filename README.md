# 3x-ui-iOS · 3x-ui 面板手机版

把 VPS 上的 **3x-ui 面板**装进 iPhone：默认打开就是**全套原生 App 界面**（概览 / 入站 / 订阅 / 工具四个页签），水墨风（宣纸白、松烟墨、青黛、朱砂印），随时一键切回原版网页处理冷门设置。

> 这个 App 只是面板的客户端，本身不代理任何流量、不内置节点、不读写你的代理配置。

## 功能

### 原生 App 界面（点开服务器就是它）
- **概览**：CPU / 内存 / 磁盘进度、运行时长、Xray 状态与版本、在线客户端、累计上下行与 TCP/UDP 连接数、公网 IP；自动刷新（12 秒，可关）、手动刷新、重启 Xray（带确认）、切换服务器、直接新建入站
- **入站**：卡片列表（协议徽章、端口、备注、启停开关、流量进度、客户端数、搜索），点开进详情
  - 新建入站：VLESS / VMess / Trojan / Shadowsocks，端口手动或随机，加密 none / TLS / Reality，传输 tcp / ws / grpc，自动生成 UUID / 密码、**Reality x25519 密钥对与 shortId**、流量与到期
  - 入站详情：改备注 / 端口 / 启停、删除入站、添加客户端、客户端启停 / 删除 / 清零用量、复制链接与二维码
- **订阅与分享**：跨入站汇总所有客户端，一键复制节点链接（`vless://` `vmess://` `trojan://` `ss://`）、生成二维码、复制或扫码订阅地址（跟随面板的 `subPort` / `subPath` 设置），支持搜索与全部复制 / 分享
- **工具**：下载 `x-ui.db` 备份并分享、查看面板日志与 Xray 日志（100/200/500 行、复制、分享）、重启 Xray、重置全部流量（带确认）、重启面板、打开原版网页、切换服务器、立即上锁
- **登录**：原生界面用面板 API + 会话 cookie；没存账号时给出原生登录表单，登录成功写进钥匙串；开着两步验证或改了登录路径时，可以先在原版网页登录一次，回来刷新即可（cookie 会自动从 WKWebView 抄过来）

### 原版网页（随时切回）
- 直接加载你服务器上的 3x-ui 网页（`http://` 与 `https://` 都行，支持自定义 `webBasePath`）
- **自签证书**：每台服务器单独开关「信任自签证书」，在 `WKNavigationDelegate` 的 challenge 里放行
- **电脑版 / 手机版**一键切换：电脑版按 1280 宽渲染并缩放视口，宽表格不再被挤成一列；手机版交给 3x-ui 自己的响应式布局
- **填入保存的账号**：把钥匙串里的账号密码通过原生 setter 填进 Ant Design 登录表单（不会自动提交）
- 网页改动 100% 保留：入站、客户端、订阅、设置、Xray 日志、IP 限制……看到的和桌面上完全一样
- 文件导入 / 导出：网页里的文件选择交给 WKWebView 的系统选择器（iOS 18.4 起才允许 App 自定义上传面板，所以保持系统默认，兼容 iOS 15+）；`.db`、`.zip`、`.json` 等下载会自动存到临时目录并弹出分享面板（可直接存到「文件」）
- 订阅链接与二维码：一键提取页面里的 sub 链接、节点链接与二维码图片，可复制、分享、生成二维码
- 工具栏：后退 / 前进 / 刷新 / 首页 / 电脑版 / 填账号 / 订阅 / 复制地址 / 收起，可整条收起让位给网页
- 清除 Cookie 与缓存、在 Safari 打开、复制 / 分享当前地址
- 兼容 3x-ui v2 与 v3 的 API 差异（`inbounds/onlines` / `clients/onlines`、`update/:id` / `setEnable/:id`、`/panel/api` 与 `/panel/xui/API`），写操作失败会依次换路径兜底

### 多服务器与隐私
- 多台 VPS 面板：添加 / 编辑 / 删除 / 拖动排序，常用的一键置顶
- 列表里点一下进原生界面；长按菜单或行尾「Safari」按钮随时打开原版网页（左滑也是）
- 面板内点「服务器」图标即可 1 秒切换
- 账号密码存 **iOS 钥匙串**（`kSecClassGenericPassword`），不写进任何明文 JSON；地址存在 App 沙盒
- **隐私锁**：Face ID / 触控 ID / 设备密码，冷启动与回到前台自动上锁
- 深浅色固定为宣纸浅色，网页本身不受影响

## 安装（自签）

1. 到 Releases 下载 `3x-ui-unsigned.ipa`（每个 `build-N` 的 Release 里都有）
2. 用全能签 / TrollStore / AltStore / Sideloadly 自签安装，Bundle ID 默认 `com.lin.xui`
3. 装之前先删掉手机上的旧版本，避免签名冲突
4. 打开 App → 添加服务器 → 填地址（例如 `https://1.2.3.4:2053/你的路径`）→ 保存 → 点开

## 从源码构建

需要 macOS + Xcode 16 以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
open XUIPanel.xcodeproj
```

命令行打未签名 IPA：

```bash
xcodebuild -project XUIPanel.xcodeproj -scheme XUIPanel \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/XUIPanel.app Payload/
zip -qry 3x-ui-unsigned.ipa Payload
```

仓库里的 `.github/workflows/build-ipa.yml` 会在每次 push 后自动出包并挂到 Release。

## 结构

```
XUIPanel/
  App/        XUIApp.swift
  Models/     ServerProfile（服务器档案，密码不入库）
  Store/      ServerStore / KeychainStore / LockManager
  Web/        PanelWebController（WKWebView）/ InjectedScripts / UserAgent
  API/        PanelAPIClient（面板 API）/ PanelModels / ShareLinkBuilder / QRCodeGenerator
  Views/      服务器列表、编辑器、面板、快捷概览、入站详情、订阅、设置、锁屏、水墨样式
  Support/    UIHelpers（分享 / 弹窗 / 图片）、ConnectionTester
```

## 已知边界

- 快捷概览需要登录态：要么在网页面板里登录过（共享 Cookie），要么在服务器设置里保存了账号密码（App 会 POST `/login`）。两者都没有时会提示。
- 订阅地址按 3x-ui 默认的 `/sub/<subId>` 规则拼，若面板把订阅改到了别的端口 / 路径，请以网页里显示的为准。
- WireGuard、Dokodemo 等没有「客户端分享链接」概念的入站，只展示流量，不生成链接。
- 自签证书信任是该服务器级别的开关；面板换成公网证书后建议关掉。

## License

MIT
