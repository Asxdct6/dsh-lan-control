# 局域网控制 DSH（Android 客户端）

DSH Web UI 的 Android 薄壳：手机通过局域网连到电脑上跑的 DSH，直接在手机上控制它。
包名 `com.dsh.lancontrol`，应用名「局域网控制DSH」。

## 产物

```
dist/DSHLanControl-2.0.0-debug.apk    0.97 MB   debug 签名
```

## 安装

```powershell
C:\Android\sdk\platform-tools\adb.exe install -r "dist\DSHLanControl-2.0.0-debug.apk"
```

或把 APK 拷到手机点安装。首次安装若提示「未经检测」选「仍要安装」（debug 签名正常）。

## 连接

APK 默认连接（构建时烧入）：

```
http://192.168.1.4:8787/?token=<构建时的 token>
```

- 电脑端要保持 `dsh web --host 192.168.1.4 --port 8787 --no-open` 在跑
- 手机与电脑必须同一个 Wi-Fi
- **token 每次重启服务都会变**：变了点 App 右上角「设置」，粘贴 DSH 窗口打印的完整地址（含 `?token=`）
- 连不上时显示「无法连接到 DSH」+ 重试 / 改地址

## 图标

图标由 `tools/make_app_icon.py` 生成：显示器 + 终端提示符 `>_` + 局域网信号弧。
想换图就替换 `new_icon.png`（≥512×512 正方形）后执行：

```powershell
.\tools\apply_icon.ps1 -Source .\new_icon.png -Build
```

## 重新编译

```powershell
.\build_debug.ps1 -DshUrl "http://192.168.1.4:8787/?token=xxxx"
```

产物：`app/build/outputs/apk/debug/app-debug.apk`

## 变更记录

| 版本 | 说明 |
|---|---|
| 2.0.0 | 改名「局域网控制DSH」，包名改 `com.dsh.lancontrol`，重做图标 |
| 1.4.0 | 「设置」按钮下移，避开 DSH 页头自己的图标 |
| 1.3.0 | 修 WebView 视口（`useWideViewPort=false`），此前按桌面宽屏渲染、字极小 |
| 1.2.0 | **修闪退根因**：`errorView` 未赋值即访问（`lateinit property errorView has not been initialized`） |
| 1.1.0 | 崩溃自诊断：异常渲染到屏幕 + 下次启动弹窗 + 一键复制 |
| 1.0.0 | 首版 |

## 工程结构

```
app/src/main/AndroidManifest.xml
app/src/main/java/com/dsh/lancontrol/
  MainActivity.kt      WebView 宿主、返回键、错误页、改地址
  CrashLogger.kt       崩溃落盘 + 下次启动展示
  App.kt               注册崩溃处理器
app/src/main/res/values/strings.xml          应用名「局域网控制DSH」
app/src/main/res/mipmap-*/                    5 档图标 + anydpi-v26 自适应图标
app/src/main/res/xml/network_security_config.xml   放行局域网明文 HTTP
tools/make_app_icon.py      生成图标源图
tools/make_icons.py         生成各密度 + 自适应图标
tools/apply_icon.ps1        一键换图标
build_debug.ps1             一键编译
dsh-web-wlan.cmd            在 192.168.1.4:8787 起 DSH Web
```

## 服务端插件（装在 ~/.dsh/profiles/web）

| 插件 | 版本 | 作用 |
|---|---|---|
| `dsh-mobile-xc` | 0.6.8 | ≤1023px 生效：overlay 抽屉、safe-area、单行输入框、轮次刻度 |
| `dsh-memory-system` | 0.2.1 | 文件型长期记忆（0.3.2 因发布不足 24h 被 pnpm 供应链策略拦下） |

配置入口：DSH 设置 → 插件 → 移动端 UI（`swipeEnabled` / `pwaEnabled` / `headerScroll` / `turnRail`）。
