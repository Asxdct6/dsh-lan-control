# 让手机连接到 Electron 桌面实例

## 为什么要单独搞一套

DSH 桌面客户端（Electron）本身就是一个 web 服务，但它对外只做了三件事：

1. 只监听 `127.0.0.1:<随机端口>`，每次启动端口都会变
2. 鉴权不是 URL token，而是 **HMAC 签名的 cookie**（`authority` 绑定 `127.0.0.1:<端口>`）
3. 渲染进程通过 `dsh-app://` 自定义协议走**进程内直连**，完全不需要 token

结果是：token 不写盘、不在渲染进程、也不在任何配置文件里，只活在主进程内存。
所以你没法像 `dsh web` 那样把地址抄下来给手机用。

## 思路

```
手机 ──https://<host>:8444──► 本地反向代理 ──► 127.0.0.1:<动态端口>
                                   │
                                   ├─ 改写 Host / Origin 为回环地址（过 host-trust fence）
                                   └─ 替换 Cookie 为从主进程抓到的签名 cookie
```

三个组件：

| 组件 | 作用 |
|---|---|
| `capture-cookie.js` | 通过 `--inspect` 连主进程，hook `globalThis.fetch`，从下一次 API 请求里截下 `dsh-auth-*` cookie |
| `proxy.js` | 无状态反向代理，每个请求重读状态文件；改写 Host/Origin/Cookie，并隧道 WebSocket |
| `supervisor.ps1` | 守护循环：确保代理在跑 → 探测是否 200 → 不正常就重新抓 cookie |

客户端重启后端口变化 → cookie 失效 → 代理返回 401/503 → 守护进程自动重抓。实测自愈 10 秒内完成。

## 前置条件

桌面客户端必须带两个调试参数启动：

```
DeepSeek Harness.exe --remote-debugging-port=9222 --inspect=9229
```

改快捷方式的目标参数即可（开始菜单 → 右键属性）。**每次启动都要带上**，否则桥接不可用。

## 使用

```powershell
# 1. 抓一次 cookie（需要客户端已启动）
node capture-cookie.js

# 2. 起代理
node proxy.js 8791

# 3. 暴露到 tailnet（HTTPS 证书需在 Tailscale 后台开启）
tailscale serve --bg --https=8444 http://127.0.0.1:8791

# 4. 守护（可选，推荐）
.\supervisor.ps1
```

然后把手机上的 DSH 客户端地址设为 `https://<你的机器>.<tailnet>.ts.net:8444/`。

## 注意

- 抓 cookie 会**触发一次渲染进程重载**（如果没有新的 API 请求），画面会闪一下
- 守护进程需要能跑 PowerShell 且不在前台弹窗：用 `wscript` + 隐藏窗口启动，不要用 WMI 直接拉 powershell（会弹终端窗口）
- 这套做法依赖客户端内部实现（`--inspect`、cookie 校验、fetch），**升级 DSH 后可能失效**
- 只适合连接自己的机器；不要把 8791 直接暴露到公网
- `proxy.js` 会把所有请求的 Cookie 统一替换成抓到的那个，因此**不要用它挂多个账号**
