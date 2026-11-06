# ReviewX

ReviewX 是一款面向 X 的原生 Android 客户端，使用 Kotlin 和 Jetpack Compose。支持双时间线、探索与搜索、帖子互动、图片画廊、视频播放、WebDAV 备份及本地设置。

## 构建

需要 JDK 17 和 Android SDK 36。在仓库根目录配置 Android SDK 路径后，可运行：

```powershell
.\gradlew.bat :app:testReleaseUnitTest :app:lintRelease
```

签名发布使用 PowerShell 7 和 `tool/build_release.ps1`。在本机配置 `JAVA_HOME`、`REVIEW_X_KEYSTORE`、`REVIEW_X_KEY_ALIAS` 和 `REVIEW_X_BC_PROVIDER`，通过标准输入提供 BKS 口令。脚本运行 Release 测试和 Lint，生成并核验签名后的 ARM64 APK。签名材料和 APK 保存在本机。

## 升级与备份

Compose 版沿用包名 `com.review.x`。使用相同签名安装时会更新旧版。应用可只读导入旧版的受支持设置和会话，升级前可先备份数据。Android 的常规安装流程不支持直接安装较低版本号的 APK。

WebDAV 默认使用全量安全备份，排除会话和 WebDAV 密码。全量备份含明文凭据，请妥善保管。

源代码遵循 [MIT 许可](LICENSE)。第三方许可见 [THIRD_PARTY_NOTICES.md](app/src/main/assets/THIRD_PARTY_NOTICES.md)。
