# ZFxF Museum — iPhone 原生宿主 v0.1

这是单独的 **iOS App 工程**，与网页版、ZFxF 藏信地图的项目互不覆盖。

## 安装到你的 iPhone

1. 在 Mac 上打开 `ios/Museum.xcodeproj`（已提供 Xcode 工程，无需安装 XcodeGen）。
2. 点击顶部蓝色 `Museum` 项目图标 → **Signing & Capabilities** → 选择你自己的 Apple Developer Team。
3. 如果当前 Bundle ID 不能注册，改成你专属的，例如 `com.<你的标识>.zfxfmuseum`。
4. 选择真实 iPhone → 按 Xcode 的 **Run ▶**。

支持 iOS 17+；没有账号、密码、位置和照片需要预先配置，也不会自动申请定位权限。首次使用需联网访问我们的网站。

## 已有功能

- 首页保留 Museum 网页的真实 UI；两位原作者的画、纸纹、动画、字体仍由上游网页渲染。**没有重新画展厅 UI**。
- 两间展厅都能通过原版入口进入；iOS 原生左上角小房子可回首页。
- iOS WKWebView 保持网页内部手势和滑动逻辑，外部网站交给系统浏览器。
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
- 通知权限只在设置中明确按按钮后申请。

## 未完成

- 美国 VPS 的 Ephemera 私人后端和 Sky 同步桥已部署，且经过匿名访问 401／认证访问 200 测试。
  但 App 不内置口令：仍要在设备上输入你自己的私人服务地址和 her 口令。
- 目前私人后端没有已完成的真实约会，所以 App 在私人云端为空时会继续展示原作者示例照片；
  **不能把示例当成用户自己的回忆**。
- 需要真机验证首次联网、跨展厅返回、HEIC 照片和长时同步表现。
- 没有后台定位；ZFxF 隐藏信件地图仍是另一个独立项目。
- GitHub Actions 产出的是**无签名的 iOS 模拟器 .app**（用于构建验证），不能直接安装到真实 iPhone。真实 iPhone 的安装需要在 Mac/Xcode 使用你的签名。

## 安全边界

- 不在公开 museum 仓库内放入任何私密照片、信件、坐标或访问口令。
- 约会服务的 WebKit 原生桥只给自己配置的服务原点下的 `/app/` 页面。
- 上游照片读取使用 `PHPicker`：用户选择哪张才读取哪张，原图不转换压缩。
- 使用前请阅读仓库根目录 `LICENSES.md`；上游授权**禁止商用**。
- 复用原作者的 iOS 嵌入代码来自 `sources/ephemera-date/examples/swiftui-host`，在本地只做路由、凭证和隐私安全改动。

## 编译验证

```sh
xcodebuild -project ios/Museum.xcodeproj -scheme Museum -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```
