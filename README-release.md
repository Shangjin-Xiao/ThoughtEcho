# 心迹应用发布指南

本指南详细说明如何使用GitHub Actions自动构建并签名Android APK。

## 1. 准备签名密钥

### 1.1 创建密钥库文件

可以使用Android Studio或通过命令行创建密钥库：

```bash
keytool -genkey -v -keystore xinji-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias xinji
```

运行此命令后，请按照提示填写相关信息并记住以下重要信息：
- 密钥库密码 (keystore password)
- 密钥密码 (key password)
- 密钥别名 (key alias)

### 1.2 将签名密钥转换为Base64格式

**Windows系统：**
```bash
certutil -encode xinji-key.jks keystore_base64.txt
```
打开生成的 `keystore_base64.txt` 文件，复制从 `-----BEGIN CERTIFICATE-----` 到 `-----END CERTIFICATE-----` 之间的所有内容（包括这两行）。

**macOS/Linux系统：**
```bash
base64 xinji-key.jks > keystore_base64.txt
```
复制 `keystore_base64.txt` 中的所有内容。

## 2. 配置GitHub仓库Secrets

1. 在GitHub仓库页面，点击 `Settings` 选项卡
2. 选择左侧菜单的 `Secrets and variables` -> `Actions`
3. 点击 `New repository secret` 添加以下密钥：

   | 名称 | 说明 | 示例 |
   |------|------|------|
   | `KEYSTORE_BASE64` | 密钥库文件的base64编码 | *从keystore_base64.txt中复制* |
   | `KEY_ALIAS` | 密钥别名 | xinji |
   | `KEY_PASSWORD` | 密钥密码 | *您设置的密钥密码* |
   | `STORE_PASSWORD` | 密钥库密码 | *您设置的密钥库密码* |

## 3. 触发自动构建

现在可以通过以下方式触发自动构建：

1. **推送到主分支**：
   - 向 `main` 或 `master` 分支推送代码时会自动触发构建

2. **创建版本标签**：
   - 创建以 `v` 开头的标签（如 `v1.0.0`）会触发构建并创建GitHub Release

3. **手动触发**：
   - 在GitHub仓库的 `Actions` 选项卡中手动触发工作流

## 4. 构建结果

成功构建后，可以在以下位置获取构建结果：

1. **每次构建**：
   - 在GitHub Actions运行记录中的"Artifacts"部分可下载APK和AAB文件

2. **版本发布**：
   - 如果通过标签触发构建，将在"Releases"页面自动创建发布并附加APK和AAB文件

## 5. 本地签名配置

如需在本地构建已签名的APK，请确保：

1. 将密钥库文件 `xinji-key.jks` 放置在 `android/app` 目录中
2. 在 `android/key.properties` 文件中配置正确的密钥信息：
   ```
   storePassword=<密钥库密码>
   keyPassword=<密钥密码>
   keyAlias=<密钥别名>
   storeFile=../app/xinji-key.jks
   ```

## 常见问题

1. **构建失败，提示找不到签名密钥**
   - 检查GitHub Secrets是否正确配置
   - 确认密钥库的base64编码没有包含额外的换行符或空格

2. **无法安装构建的APK**
   - 确保使用相同的签名密钥库进行构建
   - 如需更换签名密钥，必须更改应用的版本号