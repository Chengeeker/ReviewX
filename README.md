<div align="center">

# ReviewX

**一款面向 X（原 Twitter）的 Flutter 客户端，专注于时间线阅读与轻量互动。**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20arm64--v8a-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

*Material Design 3 界面，支持浅色、深色和动态配色。*

---

</div>

## 🌟 功能与设计

### 🏠 时间线与探索

- **首页时间线**：切换“为你推荐”和“正在关注”，显示内嵌媒体和帖子互动；连续回复会依据真实回复关系用头像连线呈现为一组对话。
- **快速重开**：本机按账号保留有限的资料和首页首屏快照，打开时先显示已有内容，再向 X 刷新；快照不含登录 Cookie 或翻页游标。
- **探索**：浏览 X 返回的趋势及地区信息、推荐关注与搜索结果。
- **侧边栏**：进入个人主页、书签、通知和本机浏览历史。

### 📝 阅读与互动

- 阅读帖子详情、回复、用户帖子/媒体列表和关系列表；支持关注、点赞、转发、书签以及文字发帖、回复和引用。
- 回复支持相关、最近、喜欢排序；详情中显示回复对象和会话层级，引用内容单独呈现，正文与媒体采用全宽排版。
- 个人主页支持推文/亮点、回复、转推、照片/视频、文章及自己的喜欢；资料统计兼容 X 新旧字段。
- 查看 X 返回的文章、链接卡片和投票信息；图片支持原图查看、缩放和保存。
- 视频播放器复用 Review 的倍速、清晰度选择、横竖屏切换和手势控制；底部提供评论、转发、喜欢和书签，支持视频保存与分享。切换媒体或进入后台时暂停播放，不提供小窗播放。阅读设置可开启默认静音，右侧滑动调整应用内音量，不修改手机系统媒体音量。
- 对 X 响应中提供完整中文译文的帖子，可选择自动显示 Grok 翻译，也可在帖子内手动切换原文/译文。
- 通过设置调整主题、帖子显示和阅读样式；设置支持 WebDAV 备份与恢复。
- 已登录时可在设置页查看并复制当前 X 登录 Cookie。
- 网络设置提供自动、直连、手动 HTTP 代理及匿名连接测试，覆盖应用内 API、图片、视频和下载；保存后完全关闭并重新打开应用生效。直连仍受手机 VPN 路由影响；手动代理需填写实际地址和端口，目前不支持 SOCKS、代理认证、PAC 或机场订阅。

### 🔐 账号与数据

- 当前登录方式为手动输入 X Cookie；应用会验证会话后，将必要 Cookie 保存在 Android 加密存储中。
- 请求 X 内容时，会话 Cookie 会发送到 X 的服务端点。项目不提供自有账号代理服务；不要在 Issue、截图或日志中粘贴 Cookie。
- 设置备份采用字段白名单，不包含 X 会话、WebDAV 密码或浏览历史。时间线与资料快照保存在本机并按账号隔离；退出账号时删除该账号快照。
- 图片由 ExtendedImage 缓存在 Android 临时目录，系统可能回收。应用会按容量和时间上限整理缓存。
- 后台通知由 Android WorkManager 定期检查，通常至少间隔 15 分钟，不是实时推送。

---

## 🏗️ 项目结构

```text
lib/
├── core/                     # 主题、存储、缓存、备份、媒体与通用组件
├── presentation/             # 首页、时间线、帖子、探索、登录、设置等页面
├── twitter/
│   ├── api/                  # X 请求和交易头
│   ├── auth/                 # Cookie 会话与账号状态
│   ├── cache/                # 本地首页/资料快照
│   ├── models/               # 用户、帖子和媒体模型
│   └── repositories/         # X 数据适配层
└── main.dart

android/                      # Android 容器、通知和启动器资源
assets/                       # X 请求参数、交易数据与应用图标
licenses/                     # Review 与交易头组件的 MIT 声明
tool/                         # X 协议/交易数据刷新、Release 构建与 APK 校验脚本
```

ReviewX 源码采用 MIT 许可。第三方来源和许可说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，其中包括 Review 组件和交易头编码/数据的独立 MIT 声明。

---

## 🚀 开发与构建

### 环境要求

- Flutter 3.x / Dart 3.5 或更新版本
- JDK 17
- Android SDK，项目使用 Android API 36 编译，最低支持 API 24
- 目标架构：`arm64-v8a`

### 获取依赖、运行和检查

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

构建 Debug 开发 APK：

```bash
flutter build apk --debug --target-platform android-arm64
```

### 构建签名 Release APK

Release 签名密钥不包含在仓库中。`tool/build_release.ps1` 从环境变量读取密钥路径、别名、JDK 路径和 Bouncy Castle Provider JAR 路径，并从标准输入读取密钥口令；临时 PKCS12 文件会在脚本结束时删除。

脚本会先检查 JDK 管道。如果 Windows 的 Unix 域套接字连接导致管道初始化失败，脚本会临时启用 JDK 17 的 TCP 回环兼容方式，再次验证后才构建。临时 Java agent 在构建结束时删除，原有进程环境恢复；此处理不会打包进 APK。

PowerShell 7 示例（把路径和别名改成自己的值；不要把口令写进脚本或提交到仓库）：

```powershell
$env:JAVA_HOME = 'C:\Path\To\JDK-17'
$env:REVIEW_X_KEYSTORE = 'C:\Path\To\release.bks'
$env:REVIEW_X_KEY_ALIAS = 'your-key-alias'
$env:REVIEW_X_BC_PROVIDER = 'C:\Path\To\bcprov-jdk18on.jar'

$secure = Read-Host 'Keystore password' -AsSecureString
$handle = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($handle)
  $password | pwsh -NoProfile -File .\tool\build_release.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($handle)
  $password = $null
  $secure.Dispose()
}
```

Release APK 元数据、签名、ABI 和 16 KiB 原生库对齐可用以下脚本检查：

```powershell
.\tool\verify_release.ps1 -Apk .\Review_X_v<version>.apk
```

---

## ⚠️ 项目说明

- ReviewX 是非官方第三方客户端，与 X Corp. 无隶属关系。应用使用的 X 网页端接口并非稳定公开 API，登录和数据读取行为可能随 X 的调整而变化。
- Cookie 登录只适用于用户有权访问的 X 账号。请勿分享个人 Cookie；遇到登录或会话问题时应在应用内重新验证或退出账号。
- 媒体上传、私信和原生投票写入尚未实现；投票可在 X 网页中操作。
- 成功编译和静态 APK 核验不代表已完成真实账号或 Android 设备验收。
