# 拾光集 Shelf

> **拾取属于你的时光碎片**
>
> 一款基于 Flutter 开发的个人本地媒体库，将小说、漫画、视频与音乐统一收纳，让每一份内容都真正属于你。

---

## ✨ 愿景

在流媒体订阅无处不在的时代，你的书架、影碟柜和唱片架却散落在不同的 App 与会员墙之后。

**拾光集**想做的是：
- **归于一处** —— 小说、漫画、视频、音乐，四种媒介，一个书架
- **真正拥有** —— 文件存在你的设备里，而非某个平台的到期列表中
- **沉浸体验** —— 打开即读、点击即播，UI 在需要时呈现，在沉浸时隐去
- **隐私为先** —— 本地数据库、生物识别锁、私密空间，你的收藏只有你能看

---

## 📚 当前已实现

### 四大媒介，统一书架

| 媒介 | 支持格式 | 核心体验 |
|------|---------|---------|
| **小说** | TXT（自动分章、UTF-8/GBK 智能识别）、EPUB、PDF、MOBI/AZW3 | 横屏分页 / 竖屏滚动、四色主题、字体定制、书签、全文搜索 |
| **漫画** | ZIP/CBZ、RAR/CBR、PDF、 loose 图片文件夹 | 双指缩放、预加载、LRU 缓存、缩略图导航、日漫 RTL 模式、屏幕方向锁定 |
| **视频** | MP4、MKV、AVI 等全格式（media_kit） | 手势控制（左亮度 / 右音量 / 横划 seek）、长按 2× 变速、字幕支持（SRT/ASS/VTT）、音轨切换、多比例、剧集自动识别（`S01E01`） |
| **音乐** | MP3、FLAC、WAV、AAC、OGG、M4A | 黑胶唱片 + 唱臂动画、封面驱动的动态模糊背景、LRC 歌词聚光灯、5 段 EQ、睡眠定时、桌面歌词（Android）、后台播放通知 |

### 内容导入与管理

- **本机导入** —— 单文件 / 整文件夹选择，自动识别媒体类型
- **WiFi 传输** —— 同局域网内通过浏览器上传，无需数据线
- **自动扫描** —— 启动时增量扫描 Downloads 目录，自动入库
- **安全导入** —— 六阶段 staging 导入管线，失败可回滚，不污染已有数据
- **回收站** —— 软删除保留 30 天，误删可一键恢复
- **私密空间** —— 指纹 / 面容识别解锁，隐私内容与普通书架完全隔离
- **自定义封面** —— 从相册选取，打造个性化书架
- **数据备份** —— ZIP 导出全库，换机或重装后可完整恢复

### 云存储与同步

内置多协议云存储子系统，支持将云端资源下载到本地阅读：

| 协议 | 功能 |
|------|------|
| **WebDAV** | 通用网盘（坚果云、群晖等） |
| **S3 / MinIO** | 对象存储 |
| **阿里云盘** | OAuth2 登录，refresh_token 换流 |
| **123云盘** | 官方 API |
| **Jellyfin / Emby** | 媒体服务器直联 |
| **飞牛OS** | NAS 本地 WebDAV |

凭证通过 `flutter_secure_storage` 加密存储，云端文件可浏览、下载、加入离线缓存。

### 智能功能

- **小说自动分章** —— 基于正则与启发式规则，自动识别 TXT 章节目录
- **漫画系列自动聚合** —— 扫描时自动将同文件夹图片识别为系列与章节
- **视频元数据刮削** —— TMDB 自动匹配海报与影片信息（需配置 API Key）
- **音乐元数据读取** —— ID3/FLAC 标签自动提取封面、艺术家、专辑

---

## 🎨 设计特色

拾光集的视觉风格深受 **Apple Human Interface Guidelines** 启发，追求「少即是多，但少要有温度」。

- **品牌色琥珀** `#D4A574` —— 替代冰冷的系统蓝，像午后阳光落在书页上
- **四档圆角体系** —— 8 / 12 / 16 / 全圆，统一卡片、按钮与弹窗
- **8pt 网格间距** —— 从容的呼吸感，不拥挤也不空洞
- **OLED 纯黑暗夜模式** —— `#000000` 背景 + `#1C1C1E` 卡片，夜间阅读不刺眼
- **有节制的动效** —— 转场、列表入场、黑胶旋转，每一帧都有目的

> *克制而不冷漠，专业而不傲慢，慢节奏但响应迅捷。*

---

## 🛠️ 技术栈

| 领域 | 选型 |
|------|------|
| 框架 | Flutter 3.x + Dart |
| 状态管理 | Provider |
| 数据库 | sqflite（SQLite），16 张表覆盖全业务 |
| 视频播放 | media_kit（跨平台 libmpv） |
| 音频播放 | just_audio + background service |
| 漫画阅读 | photo_view |
| 电子书解析 | epubx + pdf_render + 自定义 TXT/MOBI 解析 |
| 网络 / 云存储 | dio + webdav_client + minio |
| 安全存储 | flutter_secure_storage |
| 生物识别 | local_auth |
| WiFi 传输 | shelf HTTP 服务器 |

---

## 🚀 快速开始

### 环境要求

- Flutter SDK `>=3.0.0 <4.0.0`
- Android SDK（API 34）
- JDK 17

### 运行

```bash
# 克隆仓库
git clone https://github.com/sunlightsl/shelf.git
cd shelf

# 获取依赖
flutter pub get

# 运行到设备
flutter run

# 或构建 Release APK
flutter build apk --release
```

### 配置 Flutter 国内镜像（中国大陆用户）

```bash
# PowerShell
[Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", "https://mirrors.tuna.tsinghua.edu.cn/dart-pub", "User")
[Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "https://mirrors.tuna.tsinghua.edu.cn/flutter", "User")
```

---

## 📌 已知待完善

拾光集仍在持续迭代中，以下是我们正在努力的方向：

- [ ] **EPUB/MOBI 原生阅读器** —— 当前 EPUB 依赖 epubx 基础渲染，复杂排版待优化
- [ ] **PDF 阅读器增强** —— 标注、目录导航、夜间反色
- [ ] **视频海报墙** —— 向 Infuse / VidHub 看齐的精美海报展示
- [ ] **Webtoon 条漫模式** —— 纵向无缝滚动阅读
- [ ] **更多原生云 API** —— 百度网盘、OneDrive 等直链支持
- [ ] **数据库加密** —— 本地书库敏感字段加密
- [ ] **播放统计** —— 音乐与视频的年度回顾、时长统计

---

## 🤝 欢迎参与

拾光集是一个开源的个人项目，欢迎任何形式的贡献：

- 🐛 提交 Bug 或崩溃反馈
- 💡 提出功能建议或 UI 改进
- 🌍 帮助完善国际化（目前以中文为主）
- 🎨 分享你的设计灵感或品牌想法

如果你对这个项目感兴趣，可以直接提交 Issue 或 Pull Request。

---

## 📄 License

本项目采用 [MIT License](LICENSE) 开源。

> **拾光集** —— 你的内容，永远属于你。
