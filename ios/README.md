# ZFxF Museum — iPhone 原生 App v0.2

这是单独的 **iOS App 工程**，与网页版、ZFxF 藏信地图的项目互不覆盖。

## 安装到你的 iPhone

1. 在 Mac 上打开 `ios/Museum.xcodeproj`（已提供 Xcode 工程，无需安装 XcodeGen）。
2. 点击顶部蓝色 `Museum` 项目图标 → **Signing & Capabilities** → 选择你自己的 Apple Developer Team。
3. 如果当前 Bundle ID 不能注册，改成你专属的，例如 `com.<你的标识>.zfxfmuseum`。
4. 选择真实 iPhone → 按 Xcode 的 **Run ▶**。

支持 iOS 17+。App 不会在启动时自动申请定位；只有在「附近的信」点定位或主动开启自动发现时才申请相关权限。两间原作展厅的内容目前仍需联网加载；原生首页的图片已打包在 App 里。

## 已有功能

- 首页是 **SwiftUI 原生页面**，使用原作者的天空、肖像、纸张和信封素材；它并不是 GitHub Pages/PWA 的快捷方式。首页排版由原生组件实现，可能与网页预览存在少量差异；两间展厅的原版字体、内部动画和纸品交互仍由上游网页渲染。
- 两张原生卡片进入独立的内部展厅：Shelf 的 WKWebView 以及 Ephemera 官方 WKWebView 原生嵌入/试玩模式。原生「纪念馆」返回按钮可回首页，点卡片不会跳出到 Safari。展厅仍使用远程网页资源，当前**未打包为完全离线展厅**。
- iOS WKWebView 保持网页内部手势和滑动逻辑；非信任的外部页面从主展厅拦截，不会因为普通跳转自动拉起系统 Safari。官方 Ephemera 页面内部的 `openExternal` 仍保留原作者设计的 SFSafariViewController 外链行为。
- 右上角小齿轮只负责私人约会服务连接，不影响原来的展厅画面。
- **未配置私人 Ephemera 服务时**：打开原作者的演示版（假数据，不是你的真实约会）。
- 配好私人服务后，打开云端美术馆会自动同步**已结束的约会**和上传的照片，
  使用原版 Sky 烤相纸；照片翻面可进入原版 Ephemera 的对应纪念盒。
  同一张照片只在约会里上传一次，不需要重复整理。
- **配置后**：点击 Ephemera 会打开原作者 v1 原生嵌入协议页面：
  - 使用原作者的 SwiftUI / WKWebView 宿主代码及原版内部 UI；
  - 本地 PHPicker 可以把原始照片交给私人服务（不需要整个照片库权限）；
  - Edge Swipe 返回、背景生命周期、键盘、安全区、外链都接入原协议。
- 服务地址保存在本机 UserDefaults，访问口令保存在**本机 Keychain**；都不进入 GitHub、URL 或日志。服务仅支持 HTTPS。
- 「附近的信」使用 **CoreLocation + MapKit**。手动查看蓝点不会上报坐标；只有主动连接原 ZFxF 私人地图、开启「经过地点自动发现」后，iOS 才用模糊的公开圈设置有限个地理围栏。进入模糊圈时发送**一次当前位置**给原 ZFxF `/api/location` 核验，原地图服务端可能保留该次到访点；不会持续在后台上传 GPS 轨迹，也不会在客户端泄露封存信件的精确坐标。需要定位「始终允许」才能启用后台围栏。
- 通知权限只在设置明确按按钮或主动开启自动发现时申请。

## 未完成

- 美国 VPS 的 Ephemera 私人后端和 Sky 同步桥已部署，且经过匿名访问 401／认证访问 200 测试。
  但 App 不内置口令：仍要在设备上输入你自己的私人服务地址和 her 口令。
- 目前私人后端没有已完成的真实约会，所以 App 在私人云端为空时会继续展示原作者示例照片；
  **不能把示例当成用户自己的回忆**。
- 需要真机验证首次联网、跨展厅返回、HEIC 照片和长时同步表现。
- 没有后台**连续**定位；可自愿开启系统地理围栏。ZFxF 隐藏信件地图仍是独立项目，只读取其已有脱敏 API 并在确认入圈时向它提交一次坐标；原地图本身没有被搬进纪念馆。
- GitHub Actions 产出的是**无签名的 iOS 模拟器 .app**（用于构建验证），不能直接安装到真实 iPhone。真实 iPhone 的安装需要在 Mac/Xcode 使用你的签名。

## 安全边界

- 不在公开 museum 仓库内放入任何私密照片、信件、坐标或访问口令。
- 约会服务的 WebKit 原生桥只给自己配置的服务原点下的 `/app/` 页面。
- 上游照片读取使用 `PHPicker`：用户选择哪张才读取哪张，原图不转换压缩。
- 使用前请阅读仓库根目录 `LICENSES.md`；上游授权**禁止商用**。
- 复用原作者的 iOS 嵌入代码来自 `sources/ephemera-date/examples/swiftui-host`，在本地只做路由、凭证和隐私安全改动。

## 更新手机上的 App

仓库改动不会自动更新已经安装在 iPhone 上的 App。Mac 上已有克隆时先 `git pull`，然后打开 `ios/Museum.xcodeproj`，选择已连接的真实 iPhone，在 Signing & Capabilities 选择自己的开发者团队并点击 **Run ▶**。不要点仓库的 GitHub Pages 链接来判断原生版本；那里始终是独立的网页版预览。

## 编译验证

```sh
xcodebuild -project ios/Museum.xcodeproj -scheme Museum -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```
