# ZFxF · The Museum of Us

**两间展厅，一座私人纪念馆。ZFxF 地图／藏信仍然单独保留。**

这是念念新建的 museum 仓库。**以原作为准**，不改动 Shelf in the Sky 和
Ephemera 的字体、排版、相纸、天空、火漆、纸品和内部交互。

## 📱 iPhone 应用（已提交并通过 Xcode 模拟器构建）

- 原生工程：[`ios/Museum.xcodeproj`](ios/Museum.xcodeproj)（SwiftUI + WKWebView，iOS 17+）。
- [安装、签名和当前功能说明](ios/README.md)。
- iOS 宿主直接显示已经部署的网页两间展厅；原画、相纸、火漆信封、排版和内部动画**完全沿用两个上游项目**。
- 约会服务如果接入私人 HTTPS 后端，可通过 Ephemera 原生桥使用原图选择、纪念盒和通知；口令仅在设备钥匙串里，默认只有演示数据。
- CI 已验证项目可在 iOS 模拟器环境正常编译。真实 iPhone 需用自己的 Apple Developer Team 在 Xcode 签名安装。
- 私人回忆与跨展厅同步仍待接入，ZFxF 地图软件保持单独存在。

## 已经完成

- 首页只是一个非常轻的入口。卡片直接使用原项目的图像、纸纹和字体。
- gallery/：完整的 **Shelf in the Sky** 原始前端。天空、雾、翻相纸、
  照片墙和一叠相片三种模式。
- dates/：**Ephemera** 原始视觉与互动演示（官方 demo 模式，假数据和快进时钟）。
  信封、邀请函、连票、地图和纪念盒来自原项目。
- 2 个项目通过**独立锁定版本的 Git submodule** 引入，不改原始 CSS／组件。
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
- index.html — 只负责选择两个展厅的入口，不承担展厅视觉设计。
- scripts/build-preview.sh — 生成不含私有信息的浏览器演示。
- scripts/check-preview.sh — 校验素材与隐私、验证两间展厅都在。
- .github/workflows/preview.yml — GitHub Pages 自动构建与部署。

> ZFxF makes moments. Our museum keeps them.

## 🔗 两间展厅的数据互通

已加入独立的私有同步服务：`bridge/`，可将 Ephemera 已结束的约会
及有效上传照片同步至**私有版** Shelf in the Sky。照片由原作者的
烤相纸程序处理，翻面可以点击回到同一天的 Ephemera 纪念盒。

- 互通代码与端到端自动测试见 [bridge/README.md](bridge/README.md)。
- iOS 配置私人 HTTPS 服务后，打开云端美术馆可进行同步。
- 公开 GitHub Pages 仍只展示官方的**示例照片和演示约会**，
  无需把私人回忆上传到 GitHub。
- 在没有配置、部署或通过安全检查之前，iOS 会明确提示同步不可用，
  自动回到公开示例，不假装已经互通。
