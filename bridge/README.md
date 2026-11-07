# ZFxF Museum · 真正互通（私有照片 / 约会纪念盒）

这里做的是**数据互通**，不是把两个漂亮网页强行重新画成同一套 UI。

- **Ephemera 是约会的唯一数据源。** 她在原作中拆邀请函、检票、
  拍照和补写，所有资料保留在原来的私有约会后端。
- **Sky 是回忆的展示层。** 打开私人云端相册时，iOS 发送一次带
  Bearer 的后台 sync；服务端只读 Ephemera 已完成的约会和有效照片。
- 每个已完成的约会在云中对应一张原作信封做的纪念卡；该约会附带的
  每张照片也进入云中，并按原作 `tools/bake.py` 的逻辑烤成旧相纸。
- 在云里拿起那张卡，翻面会多出「↗ 打开这一天的纪念盒」的小链接；
  iOS 导航到**同一个 Ephemera 纪念盒**，不是复制另一份假纪念盒。
- 照片新增、替换或删除之后重新同步；同步生成全新快照，切换完成
  后才替换旧快照。不会留下被删照片的公开入口。
- **正在准备、未揭晓、进行中和取消的约会一律不进入云端相册**，
  防止原作的惊喜提前被看见。

## 原作风格

Sky 的 `index.html`、油画天空、字体、照片折边、三种展示模式、
雾气和所有动画全部来自原项目。唯一扩展：照片背面根据 `boxId`
追加一个轻量文本链接；没有替换原作者的设计。

Ephemera 的原始网页完全没有改。iOS 调用其 v1 原生嵌入协议，展示
它自己的信封、票根和纪念盒。

## 私有 API

运行在**仅 127.0.0.1 监听**的独立进程后，通过 HTTPS 反向代理提供：

| 方法 | 路径 | 鉴权 | 用途 |
|---|---|---|---|
| POST | `/museum-gallery/sync` | Bearer (Ephemera her token) | 读取已完成约会并更新相册 |
| POST | `/museum-gallery/session` | Bearer | 换取 1 小时 HttpOnly Secure SameSite=Strict cookie |
| GET | `/museum-gallery/` | session cookie | 原版云端相册 |
| GET | `/museum-gallery/photos.json` | session cookie | 私有相册索引 |
| GET | `/museum-gallery/photos/*` | session cookie | 私有原图 |
| GET | `/museum-gallery/baked/*` | session cookie | 原版烤相纸 |
| GET | `/museum-gallery/assets/*` | session cookie | 原作者画、云、纹理、字体 |

浏览器没有 Bearer 的情况下连 `photos.json` 都拿不到（401）。
iOS 口令在系统 Keychain，网页只得到短期 cookie。
照片从未经过 GitHub Pages／公开 `museum` 仓库。
如果 `MUSEUM_PUBLIC_PREFIX=/date/museum-gallery`，Cookie 的 Path
自动与 Nginx 的 `/date/` 代理路径一致。

## 服务端启动（前提：私有 Ephemera 已配置）

Python 3.10+、Pillow、numpy，源项目两个 Git submodule：

~~~bash
export MUSEUM_EPHEMERA_BASE=http://127.0.0.1:8793
export MUSEUM_HER_TOKEN=<与Ephemera_HER_TOKEN相同的私有值>
export MUSEUM_GALLERY_DIR=/var/lib/museum-private/gallery
export MUSEUM_PUBLIC_PREFIX=/date/museum-gallery
python3 bridge/server.py
~~~

默认仅监听 `127.0.0.1:8794`，**不可直接对公网开放**。
代理需要先经过 TLS；公共部分 `/date/museum-gallery/` 与服务内
`/museum-gallery/` 之间由 Nginx 剥去 `/date`。
开发环境可以先用 `python3 -m unittest discover -s bridge/tests -v` 验证，
测试只使用假照片、假约会，不涉及用户真实回忆。

## 私有数据规则

- 数据默认 `/var/lib/museum-private/gallery/`（权限 0700）。
- 每次同步生成新快照，使用 symlink 原子切换，保留最近 3 代以避免
  请求中的图片断开；磁盘数据不进行公开索引。
- 正式关机/删 App/长期撤销权限时应单独决定如何清理快照。
- Pillow 暂时不能解码的 HEIC/AVIF 照片会被记录到 `unsupported` 计数，
  原图继续安全保留在 Ephemera，**不会被删除**。
- 此处当前没有做多用户、云相册共享或远程定位。
- 本项目与原来的 ZFxF 藏信地图完全隔离。

## 从私人约会返回云中

iOS 在原版纪念盒关闭后，若当前在私有云端照片里，会再次同步，
因此一场约会只需要在 Ephemera 上传一次照片。

正式启用之前请验证域名、证书、服务器权限和真实 iPhone 的 cookie／照片表现。
