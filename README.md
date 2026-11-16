# GiWiFi 助手（iOS）

GiWiFi 校园网认证的 iOS 原生客户端，对应 Android/Flutter 端 [xGiWifi](https://github.com/Mhenwa/xGiWifi) 的功能集：
**一键认证、掉线自动重连、设备身份伪装、多端（手机/平板/自定义机型）切换、完整运行日志**。

协议按 xGiWifi 的 Dart 实现逐字段对齐（AES-128-ECB + MD5 签名 + `data=` 表单体），不是网页套壳，也不依赖 WebView。

- 最低系统：iOS 16.0
- 设备：iPhone / iPad（arm64）
- Bundle ID：`com.giwifi.ios`
- 版本：1.1.0 (2)

---

## 一、功能

| 功能 | 说明 |
| --- | --- |
| 一键认证 | 探测 Portal → 账号层 `appLogin.bin` → `queryAuthState` → `authLogin` |
| 自动重连 | 每 N 秒（默认 30，可调 10–300）查一次在线状态，掉线自动重新认证 |
| 设备伪装 | 认证报文里的 `staModel` / `btype` / `staType` / `userMac` 由「设备档案」决定 |
| 多端切换 | 顶部档案胶囊一键切换：Android 手机 / Android 平板 / 小米 / 华为平板 / 自定义 |
| 设备冲突换绑 | 命中 `errorCode=43` 或「已绑定」提示时自动调用 `reBindMac`，等 4 秒重探再认证一次 |
| 运行日志 | 每一步请求与响应结果都记录，可复制反馈 |
| 指定 Portal | 设置里可填站点（默认 `http://100.100.9.2/gportal/web/login`），跳过公网探测直连 |

「设备伪装」在 iOS 上完全可行：服务端是靠报文里上报的字段判断设备类型，不需要改网卡物理地址。

### Portal 三种来源（按优先级）

1. **设置里手填**（默认已填 `http://100.100.9.2/gportal/web/login`）——直连该主机，认证接口按同主机拼接；
2. 探测 `http://115.159.209.137`，从 `301/302/307` 的 `Location` 抓 `/gportal/web/login`；
3. 兜底 `http://as.gwifi.com.cn/gportal/web/login`。

把设置里那栏清空即回到原版探测行为；站点换了只改这一栏，不用重装。

### 界面

v1.1.0 起整体换成**液态玻璃（Liquid Glass）风格**：深色极光渐变底 + 三团彩色光晕 + 半透明毛玻璃卡片，
卡片带左上高光描边、右下暗边与投影，状态环是玻璃圆盘内嵌渐变进度弧，按钮按下有回弹缩放。

iOS 26 有系统级 `.glassEffect()`，但本工程最低支持 iOS 16，所以用 `Material` + 多层描边高光手搓了等效质感
（`Sources/Views/GlassTheme.swift`），在 iOS 16–26 上观感一致，不依赖新系统 API。

---

## 二、构建未签名 IPA

### 方式 A：GitHub Actions（免费，无需 Mac）

```bash
# 1. 把本目录推到 GitHub 仓库
# 2. Actions 页手动 Run workflow（或打 tag：git tag v1.0.0 && git push --tags）
# 3. 跑完在 Artifacts 下载 GiWiFi-unsigned-ipa
```

> 注意：**私有仓库 + 免费账号拿不到 macOS runner**（job 会秒 cancelled）。要么仓库公开，要么升级 Pro/Team，要么用方式 B。
> runner 用 `macos-15`；`macos-14` 在部分账号上会报 `The configuration 'macos-14-arm64-us-default' is not supported`，`macos-13` 已退役。

### 方式 B：任意 Mac

```bash
brew install xcodegen
bash scripts/build-ipa.sh          # 产物：dist/GiWiFi-unsigned.ipa
python3 scripts/verify_ipa.py dist/GiWiFi-unsigned.ipa
```

### 目录

```
project.yml                         XcodeGen 工程描述
Support/Info.plist                  Info.plist（ATS 只开 NSAllowsArbitraryLoads）
Sources/App/GiWiFiApp.swift         入口
Sources/Core/Crypto.swift           MD5 / AES-128-ECB / javaFormUrlEncode
Sources/Core/GiWiFiProtocol.swift   常量、签名、加密、响应解析
Sources/Core/GiWifiClient.swift     认证链路
Sources/Core/NetworkIdentity.swift  本机 IP / MAC 读取
Sources/Core/TerminalProfile.swift  设备档案与设置模型
Sources/Core/AppStore.swift         状态机、自动重连、日志
Sources/Core/Keychain.swift         密码存档
Sources/Views/                      SwiftUI 界面
scripts/                            构建、打包、图标、校验脚本
.github/workflows/                  CI
```

---

## 三、安装

未签名 IPA 需要重签后安装：

1. **Sideloadly**（Windows / macOS）：拖入 ipa，填自己的 Apple ID，Start。
2. **AltStore / SideStore**：自签证书，7 天续签（付费开发者账号 1 年）。
3. **TrollStore**（iOS 14.0–16.6.1 且支持 CoreTrust 漏洞的机型）：可直接安装未签名 ipa，无 7 天限制。

覆盖安装同一 Bundle ID 会保留已保存的账号与档案。

---

## 四、协议要点（对齐 xGiWifi）

```
探测：GET http://115.159.209.137            不跟随重定向，取 Location 里的 /gportal/web/login
账号：POST http://{host}:8080/wocloud_v2/appUser/appLogin.bin
      Content-Type: text/plain;charset=utf-8
      {token, version, mac, gatewayId, data<内层 JSON 字符串，字段级 AES>}
状态：POST {portal}/gportal/app/queryAuthState   {timestamp, userIp, userName}
认证：POST {portal}/gportal/app/authLogin        {appUuid, userIp, nasName, userMac, vlan, ...}
换绑：POST {portal}/gportal/app/reBindMac        命中设备冲突时
```

签名与加密：

- `signature = md5(k1=v1&k2=v2...（按 key 字典序） + signSecret)`
- 载荷 = 排序字段串（`passwd` 先做 form 编码）+ `&sign=...`
- 整体 AES-128-ECB/PKCS7 → Base64 → form 编码 → `data=<...>`
- UA：`okhttp/3.8.0`；`nasName` 为 `GIWIFI-BAS` 时以小写上报

### `nasName` 是认证成败的关键（实测）

`authLogin` 返回 `resultCode=99 CHALLENGE_ERR_DENY` 基本只有一个原因：**`nasName` 和该 IP 实际所属的网关对不上**。

实测环境（岭南师范学院，Portal `http://100.100.9.2/gportal/web/login`）：

| 来源 | 值 |
| --- | --- |
| Portal 页面 `<input name="nas_name">` / `wlanacname` | `GiWiFi_lnsf` |
| `queryAuthState` 返回（服务端真值） | **`GiWiFi_lnsfHG`** |
| 用 `GiWiFi_lnsf` 发 authLogin | `99 CHALLENGE_ERR_DENY` |
| 用 `GiWiFi_lnsfHG` 发 authLogin | `108 账户不存在或密码错误`（说明身份层已通过） |

所以取值顺序是：**设置里手填 > `queryAuthState` 返回的 `nasName` > Portal 页面抓取**；若仍被 `CHALLENGE_ERR_DENY` 拒绝，会自动给 `nasName` 换常见后缀（`HG` / `BRAS` / …）重试一次（中间等 5 秒，避开服务端的频率限制 `102`）。

顺带一提：`queryAuthState` 是**按 `userIp` 返回该 IP 的会话**，`userName` 传什么都一样——所以 iOS 拿不到真实 MAC 时，靠它就能拿到网关侧看到的真实 `userMac` 和 `nasName`。另外 Portal 首页用 `okhttp` UA 会被 403，用浏览器 UA 才返回 200。

---

## 五、已知限制

1. **iOS 读不到真实 Wi-Fi MAC**（`getifaddrs` 恒返回 `02:00:00:00:00:00`）。程序会自动改用服务端 `queryAuthState` 返回的 `userMac`；想固定身份就在档案里手填 MAC。
2. **iOS 不允许 App 常驻后台**。自动重连在 App 前台（或刚切后台的短暂时间内）有效，锁屏久了会被系统挂起。真正的后台守护需要 MDM 或私有 API，本工程不做。
3. 只实现 GiWiFi（`gportal`）体系。其它厂商的 Portal（深澜、Dr.COM 等）不适用。
4. `service_type` 默认 1；个别学校要求 2/3，可在设置里改。

---

## 六、许可

本工程为独立 Swift 实现，未包含上游代码。协议行为参考 [xGiWifi](https://github.com/Mhenwa/xGiWifi)（MIT）与公开的 GiWiFi Portal 接口。

请只在自己拥有账号的校园网内使用。
