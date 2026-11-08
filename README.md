# ZFxF · The Museum of Us

**两间原版展厅、一段送花约会序章。ZFxF 地图／藏信仍然单独保留。**

这是念念新建的 museum 仓库。**以原作为准**，不改动 Shelf in the Sky 和
Ephemera 的字体、排版、相纸、天空、火漆、纸品和内部交互。

## 💐 新增：先收花，再赴约，最后再收花

入口：[A Date, Two Bouquets](romance/)；线上预览路径是 `/museum/romance/`。

1. Finnian 先送一束可旋转的 3D 花，点花和贺卡使用 CyberFlowerShop **原站**的交互。
2. 点击「花收好了 · 看看邀请函」**直接打开原版 Ephemera Invitation Box 首页**，不再经过另外制作的邀请过渡页。
3. 网页预览直接显示 Ephemera 官方演示界面，并保留顶部结束后收花按钮；iOS 无私人配置时直接进入原版 Ephemera 演示展厅，点「结束约会 · 收花」拿到第二束花；配置私人约会后直接进入原生 Ephemera，退出后收到第二束花。
4. 结束花保留独立寄语，回到纪念馆可继续原来的两间展厅；**这段流程不会捏造或提交真实约会记录**。

花店原项目：[frycarrot/CyberFlowerShop](https://github.com/frycarrot/CyberFlowerShop)。
因上游仓库目前没有明确的根目录代码许可证，本项目仅通过独立跨站 iframe 嵌入原作者已经公开托管的花店，**不复制、修改、再托管其源码、字体或 3D 模型**。需要联网访问原网站。只有花束码和非敏感寄语作为 iframe 地址的 URL fragment 传递给原站前端；不传私密服务的口令、照片或位置。

## 📱 iPhone 原生应用（SwiftUI 首页 + 原版展厅）

- 原生工程：[`ios/Museum.xcodeproj`](ios/Museum.xcodeproj)（SwiftUI + WKWebView，iOS 17+）。
- [安装、签名和当前功能说明](ios/README.md)。
- iOS App 使用 SwiftUI 原生首页和打包的原版天空、纸纹、肖像、信封素材；两个展厅的原版内部交互仍通过 WKWebView 渲染，点击展厅不会跳转系统 Safari。展厅目前仍联网加载，尚非完全离线版本。
- 约会服务如果接入私人 HTTPS 后端，可通过 Ephemera 原生桥使用原图选择、纪念盒和通知；口令仅在设备钥匙串里，默认只有演示数据。
- CI 已验证项目可在 iOS 模拟器环境正常编译。真实 iPhone 需用自己的 Apple Developer Team 在 Xcode 签名安装。
- 私有约会和相册已有独立的同步桥，真机需填写私人服务器地址和口令并实际验收；原 ZFxF 藏信地图保持独立。iOS 另有需主动同意的 CoreLocation 地理围栏：只利用原地图公开的模糊范围，进入范围后单次定位由原服务器判定是否真正到达，具体信息见 ios/README.md。

## 已经完成

- 首页只是一个非常轻的入口。卡片直接使用原项目的图像、纸纹和字体。
- gallery/：完整的 **Shelf in the Sky** 原始前端。天空、雾、翻相纸、
  照片墙和一叠相片三种模式。
- dates/：**Ephemera** 原始视觉与互动演示（官方 demo 模式，假数据和快进时钟）。
  信封、邀请函、连票、地图和纪念盒来自原项目。
- Shelf 与 Ephemera 两个项目通过**独立锁定版本的 Git submodule** 引入，不改原始 CSS／组件；赛博花店使用原站 iframe，不复制未授权源码。
- GitHub Actions 自动构建静态预览，不上传任何私人回忆。

## 体验方式

在仓库 Settings → Pages 选择 GitHub Actions，便可发布浏览器预览。
仓库拥有者可能需要首次手动启用 Pages。

本地测试需要 Node.js 22 和 Python 3；首次构建需下载依赖：

~~~sh
git clone --recurse-submodules https://github.com/1990786584-afk/museum.git
cd museum
./scripts/build-preview.sh ""
python3 -m http.server 8000 --directory preview
# 浏览器打开 http://localhost:8000/
~~~

注意：GitHub Pages 的路径不同，在 Actions 中使用
./scripts/build-preview.sh /museum 来正确生成资源地址。

## 目前的边界

这版是**原貌保留、能实际操作的双展厅预览版**。暂时是公开仓库，
所以只有原作提供的**示例照片和假约会**，**没有**任何念念的私人照片、
地址、日记、约会和信件。

生产版将单独启用鉴权的 Ephemera 后端和私有存储，且可选择将约会的照片
整理进 Sky；但 **目前两套数据尚未接通**。不把演示数据当成共同回忆。

## 约定

1. 永远优先用原项目已有的字体、材质、CSS 和组件，不为“统一风格”重画。
2. 分区独立，避免 CSS 全局冲突、上游许可证意外混用。
3. 以后增加私密同步时放在连接层，不覆盖上游 UI。
4. 上游版本先锁定，更新前逐项确认，不自动追新。
5. 两个上游都有 **非商业许可限制**，详见 LICENSES.md。
6. ZFxF 藏信地图（hidden-letters-map）保持独立，不在这里迁移或改动。

## 结构

- sources/shelf-in-the-sky/ — Git submodule，原版照片展厅。
- sources/ephemera-date/ — Git submodule，原版约会纸品展厅。
- index.html — 展厅入口及送花约会入口，保留两间原作展厅的外观与内容。
- romance/ — 独立薄包装层：原站 3D 花束 → 原版 Ephemera Invitation Box → 第二束花。
- scripts/build-preview.sh — 生成不含私有信息的浏览器演示。
- scripts/check-preview.sh — 校验素材与隐私、验证两间展厅都在。
- .github/workflows/preview.yml — GitHub Pages 自动构建与部署。

> ZFxF makes moments. Our museum keeps them.

## 🔗 两间原版展厅的数据互通

已加入独立的私有同步服务：`bridge/`，可将 Ephemera 已结束的约会
及有效上传照片同步至**私有版** Shelf in the Sky。照片由原作者的
烤相纸程序处理，翻面可以点击回到同一天的 Ephemera 纪念盒。

- 互通代码与端到端自动测试见 [bridge/README.md](bridge/README.md)。
- iOS 配置私人 HTTPS 服务后，打开云端美术馆可进行同步。
- 公开 GitHub Pages 仍只展示官方的**示例照片和演示约会**，
  无需把私人回忆上传到 GitHub。
- 私人引擎与同步桥已经在自有 VPS 上部署；用户仍需在 iPhone 手动填写 HTTPS 地址和私密口令。
- 在没有配置或安全检查失败之前，iOS 会明确提示同步不可用，
  自动回到公开示例，不假装已经互通。
