# -*- coding: utf-8 -*-
"""更新 README：版本号、nasName 记忆、网页表单登录、43 自动绑定。"""
import io

P = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\README.md"
s = io.open(P, encoding="utf-8").read()

s = s.replace("- 版本：1.2.0 (3)", "- 版本：1.3.4 (12)")

# 功能表补三行
old = "| 自动重连 | 每 N 秒（默认 30，可调 10–300）查一次在线状态，掉线自动重新认证 |"
new = ("| 自动重连 | 每 N 秒（默认 30，可调 10–300）查一次在线状态，掉线自动重新认证 |\n"
       "| 网页表单登录 | API 被网关拒绝时自动改走 `/gportal/Web/loginAction`（AES-128-CBC + ZeroPadding，body 为 form-urlencoded） |\n"
       "| 43 自动换绑 | 服务端返回 `bindSta` 链接时自动 GET 完成绑定并重新认证，无需手动点 |\n"
       "| 网关名记忆 | 第一次成功后记住 `nasName`（如 `GiWiFi_lnsfHG`），下次首个请求直接用，不再先撞 `CHALLENGE_ERR_DENY` |")
if old in s:
    s = s.replace(old, new, 1)

extra = """

---

## 十一、几个只有真机才看得出来的坑（1.3.x 实测）

| 现象 | 真实原因 | 处理 |
| --- | --- | --- |
| `resultCode=99 CHALLENGE_ERR_DENY` | `nasName` 与真实网关不一致（页面给 `GiWiFi_lnsf`，实际是 `GiWiFi_lnsfHG`） | 自动枚举后缀重试；成功后记住正确值 |
| 换名重试立刻回 `102 操作过于频繁` | 两条 `authLogin` 落在同一秒，网关有最小间隔 | 每次重试前固定等 5.5 秒 |
| 网页登录回 `CHALLENGE_ERR_DENY` | body 发成了 JSON；官方页面用 jQuery，序列化成 `data=..&iv=..` | 改 `form-urlencoded`，服务端就能进业务层 |
| 网页登录回 `ac is empty` | `ac` 来自「被网关拦截那一跳」的会话上下文，直连登录页拿不到 | 优先走 API 认证，网页登录只作兜底 |
| `43` 只有提示、没有按钮 | 43 的 `data` 里是 `/Giportal/index.php/Sta/bindSta?...`，GET 它即完成绑定 | 自动提交 + 重试；同时保留手动按钮 |
"""

if "只有真机才看得出来" not in s:
    s = s.rstrip() + extra

io.open(P, "w", encoding="utf-8", newline="\n").write(s)
print("README 更新完成，%d 字节" % len(s.encode()))
