# ZFxF · The Museum of Us

**两间展厅，一座私人纪念馆。ZFxF 地图／藏信仍然单独保留。**

这是念念新建的 museum 仓库。**以原作为准**，不改动 Shelf in the Sky 和
Ephemera 的字体、排版、相纸、天空、火漆、纸品和内部交互。

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
