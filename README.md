# 局域网控制 DSH

[![Build APK](https://github.com/Asxdct6/dsh-lan-control/actions/workflows/build-apk.yml/badge.svg)](https://github.com/Asxdct6/dsh-lan-control/actions/workflows/build-apk.yml)

在手机上通过局域网控制电脑上运行的 [DeepSeek Harness](https://github.com/deepseek-ai/DeepSeek-Harness)（DSH）。

一个极薄的 Android WebView 壳：把 DSH 的 Web UI 装进原生应用，配上移动端抽屉导航、自适应图标和崩溃自诊断。

![主界面](docs/screenshot-main.png)

> 这个 App **不包含** DSH 本体。DSH 仍然跑在你的电脑上，手机只是通过 Wi-Fi 访问它。

## 它解决什么

DSH 的 Web UI 在桌面浏览器里很好用，但在手机上有三个现实问题：

1. 浏览器地址栏、标签页吃掉本来就窄的屏幕
2. 每次连都要手敲 `http://ip:port/?token=...`
3. 手机浏览器切后台后页面容易被回收

这个壳把这三点收掉了：全屏、地址内置、原生 Activity 保活。

## 功能

| 功能 | 说明 |
|---|---|
| 全屏 WebView | 无地址栏，页面即应用 |
| 移动端布局 | 依赖 DSH 插件 `dsh-mobile-xc`，≤1023px 时侧边栏变成 overlay 抽屉 |
| 地址管理 | 右上角「设置」随时改连接地址，配置持久化 |
| 返回键 | 优先走 WebView 历史，退到底再退出应用 |
| 断连提示 | 连不上时显示错误页，可重试或改地址 |
| 崩溃自诊断 | 未捕获异常落盘，下次启动弹窗展示堆栈，可一键复制 |
| 自适应图标 | Android 8.0+ Adaptive Icon，5 档密度 |

## 环境要求

- 电脑：DSH 已安装，且与手机在**同一个 Wi-Fi / 局域网**
- 手机：Android 7.0+（`minSdk 24`）
- 构建：JDK 17、Android SDK（`platform-34`、`build-tools 34.0.0`）

## 快速开始

### 1. 在电脑上把 DSH 暴露到局域网

```powershell
.\start-dsh-lan.ps1
```

脚本会自动挑一个局域网 IPv4 并启动 `dsh web`，然后打印形如：

```
http://192.168.1.100:8787/?token=xxxxxxxx
```

`--host` 只接受具体 IPv4、不能用 `0.0.0.0`（DSH 的设计），所以脚本会帮你探测。

### 2. 构建 APK

```powershell
.\build_debug.ps1 -DshUrl "http://192.168.1.100:8787/?token=xxxxxxxx"
```

不带 `-DshUrl` 也行，APK 里会烧一个占位地址，首次启动时弹框让你填。

产物：`app/build/outputs/apk/debug/app-debug.apk`

### 3. 安装

```powershell
adb install -r app\build\outputs\apk\debug\app-debug.apk
```

或者把 APK 拷到手机上点安装（debug 签名，需要允许「未知来源」）。

### 4. 首次打开

- 构建时烧了真实地址 → 直接进 DSH
- 构建时是占位地址 → 弹出「连接设置」，粘贴第 1 步打印的完整地址（**要带 `?token=`**）

## 关于 token

DSH 在非回环地址上启动时会生成一次性 token，**每次重启服务都会变**。
变了之后 App 会显示「无法连接到 DSH」，点右上角「设置」粘贴新地址即可。

这是 DSH 的安全设计，不是 App 的缺陷。

## 目录结构

```
app/src/main/java/com/dsh/lancontrol/
  MainActivity.kt      WebView 宿主、返回键、错误页、地址设置
  CrashLogger.kt       崩溃落盘与下次启动回显
  App.kt               注册全局崩溃处理器
app/src/main/res/
  values/strings.xml               应用名与文案
  mipmap-*/                        5 档图标 + anydpi-v26 自适应图标
  xml/network_security_config.xml  放行局域网明文 HTTP
tools/
  make_app_icon.py     生成图标源图（显示器 + >_ + 信号弧）
  make_icons.py        生成各密度与自适应图标
  apply_icon.ps1       一键换图标
build_debug.ps1        一键编译
start-dsh-lan.ps1      在局域网 IP 上启动 DSH Web
```

## 实现要点

- **不开 `useWideViewPort`**：开了会让页面按桌面 980px 排版再整体缩放，字会小到看不清，且移动端插件的断点失效
- **`adjustResize`**：键盘弹出时页面整体上移，输入框不被遮挡
- **不使用任何第三方依赖**：只用 Android 平台 API，构建快、体积小（APK ≈ 0.95 MB）
- **放行明文 HTTP**：局域网是 `http://`，通过 `network_security_config` 显式声明

## 已知限制

- 纯壳，DSH 必须单独运行
- 依赖局域网直连；公网访问需要自建隧道，且 DSH 的 host 校验会拦
- debug 签名，不适合分发
- 仅在 Android 17（API 37）/ OPPO PLG110 上实测过

## License

[MIT](LICENSE)
