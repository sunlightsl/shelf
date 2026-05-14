# 本地图书馆

一个基于 Flutter 开发的本地图书馆应用，支持小说、漫画、视频的阅读和管理。设计风格参考苹果 iOS 风格，简洁优雅。

## 功能特性

- **多格式支持**
  - 小说：TXT、EPUB、PDF、MOBI、AZW3
  - 漫画：ZIP/CBZ、RAR/CBR、PDF
  - 视频：MP4、MKV、AVI

- **文件导入**
  - 从设备选择文件导入
  - 批量导入整个文件夹
  - WiFi 局域网传输（电脑浏览器上传）

- **阅读体验**
  - 小说：滑动阅读、字体调节、夜间模式、阅读进度记忆
  - 漫画：左右翻页/上下滚动、双指缩放
  - 视频：手势控制、倍速播放（预留）、进度记忆

- **书架管理**
  - 按类型分类（小说/漫画/视频）
  - 最近阅读记录
  - 收藏功能
  - 自定义封面

- **数据安全**
  - 本地数据库存储（SQLite）
  - 应用私有目录存储文件
  - 本地备份/恢复功能（支持分享备份文件）
  - 为未来 NAS 同步预留接口

## 项目结构

```
lib/
├── main.dart                 # 应用入口
├── app.dart                  # 主题配置和根组件
├── models/                   # 数据模型
│   ├── library_item.dart     # 书库项目模型
│   └── reading_progress.dart # 阅读进度模型
├── database/                 # 数据库层
│   ├── database_helper.dart  # SQLite 初始化
│   └── library_dao.dart      # 数据访问对象
├── providers/                # 状态管理
│   └── library_provider.dart # 书库状态
├── services/                 # 业务服务
│   ├── file_import_service.dart   # 文件导入解析
│   ├── cover_service.dart         # 封面提取/生成
│   ├── wifi_transfer_service.dart # WiFi 传输服务
│   └── backup_service.dart        # 备份恢复服务
├── screens/                  # 页面
│   ├── home_screen.dart      # 主框架（底部导航）
│   ├── recent_screen.dart    # 最近阅读
│   ├── library_screen.dart   # 书架
│   ├── import_screen.dart    # 导入/WiFi传输
│   ├── settings_screen.dart  # 设置/备份
│   └── readers/              # 阅读器
│       ├── novel_reader_screen.dart
│       ├── comic_reader_screen.dart
│       └── video_player_screen.dart
└── widgets/                  # 通用组件
    └── empty_state.dart      # 空状态组件
```

## 环境配置

### 1. 配置 Flutter 国内镜像（中国大陆用户）

在系统环境变量中添加：

```bash
PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub
FLUTTER_STORAGE_BASE_URL=https://mirrors.tuna.tsinghua.edu.cn/flutter
```

Windows 设置方法：
- 系统属性 → 环境变量 → 用户变量 → 新建
- 或者使用 PowerShell: `[Environment]::SetEnvironmentVariable("PUB_HOSTED_URL", "https://mirrors.tuna.tsinghua.edu.cn/dart-pub", "User")`

### 2. 确保 Android 开发环境

- Android Studio 已安装
- Android SDK（API 34）
- JDK（Android Studio 自带）

### 3. 首次运行

```bash
# 进入项目目录
cd local_library

# 获取依赖
flutter pub get

# 运行到 Android 设备/模拟器
flutter run

# 或构建 Release APK
flutter build apk --release
```

## 已知待完善项

1. **EPUB 阅读器**：当前仅 TXT 有基础阅读器，EPUB/PDF/MOBI 需要集成专用解析库
2. **PDF 阅读器**：当前未实现，可使用 `flutter_pdfview` 或 `pdfrx`
3. **视频字幕**：当前未实现外挂字幕加载
4. **封面自定义**：UI 入口已预留，需要接入 `image_picker`
5. **NAS 同步**：数据层已预留 `deviceId` 字段，后续可扩展 WebDAV/SMB 协议

## 技术栈

- **框架**: Flutter 3.x + Dart
- **状态管理**: Provider
- **数据库**: sqflite (SQLite)
- **视频播放**: media_kit
- **漫画阅读**: photo_view
- **文件解压**: archive

## 设计规范

- 圆角卡片（16px）
- 底部毛玻璃导航栏
- iOS 风格转场动画（CupertinoPageRoute）
- 系统字体栈（SF Pro / Roboto）
- 配色：主色 #0071E3，背景 #F5F5F7
