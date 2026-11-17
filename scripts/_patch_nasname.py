# -*- coding: utf-8 -*-
"""1) 重试间隔恢复为固定 5.5 秒（DENY 后立刻重发会被判 102 频繁）。
2) Result 带上实际用到的 nasName，成功时由 AppStore 记住，下次第一次就用对，不再白跑 DENY。
"""
import io

CLIENT = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\Sources\Core\GiWifiClient.swift"
STORE = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\Sources\Core\AppStore.swift"

# ---------- GiWifiClient ----------
c = io.open(CLIENT, encoding="utf-8").read()

old = '''                    let throttled = firstAuth.resultCode == 102 || firstAuth.message.contains("频繁")
                    log("认证被拒（\\(firstAuth.message)），改用 nasName=\\(candidate) 重试\\(throttled ? "（等 5 秒避开频率限制）" : "")")
                    if throttled { try? await Task.sleep(nanoseconds: 5_200_000_000) }'''
new = '''                    // 网关对同一账号 + 同一 IP 的 authLogin 有最小间隔：
                    // 收到 DENY 立刻换名重发，第二发会直接判 102「操作过于频繁」。
                    // 所以每次重试前都等，不只是 102 才等。
                    log("认证被拒（\\(firstAuth.message)），改用 nasName=\\(candidate) 重试（等 5.5 秒避开频率限制）")
                    try? await Task.sleep(nanoseconds: 5_500_000_000)'''
if old not in c:
    raise SystemExit("锚点 A 没找到")
c = c.replace(old, new)

old = '''        var needsRebind: Bool = false
        /// 43 时服务端给的换绑链接（GET 即完成绑定）。
        var bindPath: String = ""'''
new = '''        var needsRebind: Bool = false
        /// 43 时服务端给的换绑链接（GET 即完成绑定）。
        var bindPath: String = ""
        /// 本次真正用上的网关名，上层记下来，下次第一次就用对。
        var nasName: String = ""'''
if old not in c:
    raise SystemExit("锚点 B 没找到")
c = c.replace(old, new)

# 三处成功/43 返回补 nasName
old = '''                    if let retry, retry.isSuccess {
                        return Result(online: true, message: retry.displayText,
                                      portalOrigin: retryContext.portal.absoluteString,
                                      serverMac: retryContext.userMac, authState: retry.authState)
                    }'''
new = '''                    if let retry, retry.isSuccess {
                        return Result(online: true, message: retry.displayText,
                                      portalOrigin: retryContext.portal.absoluteString,
                                      serverMac: retryContext.userMac, authState: retry.authState,
                                      nasName: retryContext.nasName)
                    }'''
if old not in c:
    raise SystemExit("锚点 C 没找到")
c = c.replace(old, new)

old = '''                                      needsProfile: Self.needsProfileCompletion(retry),
                                      needsRebind: retry.requiresRebind,
                                      bindPath: retry.bindPath)'''
new = '''                                      needsProfile: Self.needsProfileCompletion(retry),
                                      needsRebind: retry.requiresRebind,
                                      bindPath: retry.bindPath,
                                      nasName: retryContext.nasName)'''
if old not in c:
    raise SystemExit("锚点 D 没找到")
c = c.replace(old, new)

old = '''            if let firstAuth, firstAuth.isSuccess {
                return Result(online: true, message: firstAuth.displayText,
                              portalOrigin: context.portal.absoluteString,
                              serverMac: context.userMac, authState: firstAuth.authState)
            }'''
new = '''            if let firstAuth, firstAuth.isSuccess {
                return Result(online: true, message: firstAuth.displayText,
                              portalOrigin: context.portal.absoluteString,
                              serverMac: context.userMac, authState: firstAuth.authState,
                              nasName: context.nasName)
            }'''
if old not in c:
    raise SystemExit("锚点 E 没找到")
c = c.replace(old, new)

io.open(CLIENT, "w", encoding="utf-8", newline="\n").write(c)
print("GiWifiClient patched")

# ---------- AppStore ----------
s = io.open(STORE, encoding="utf-8").read()

old = '''            state = .online
            detail = result.message.isEmpty ? "已认证，可以上网了" : result.message
            append("认证成功：\\(detail)")'''
new = '''            state = .online
            detail = result.message.isEmpty ? "已认证，可以上网了" : result.message
            append("认证成功：\\(detail)")
            rememberNasName(result.nasName)'''
if old not in s:
    raise SystemExit("锚点 F 没找到")
s = s.replace(old, new, 1)

# 新增 rememberNasName，塞在 persist() 之前
anchor = '''    private func persist() {'''
helper = '''    /// 记住这次真正生效的网关名，下次第一次就直连它，不再先撞一次 DENY。
    private func rememberNasName(_ name: String) {
        guard !name.isEmpty, settings.nasName != name else { return }
        var next = settings
        next.nasName = name
        settings = next
        persist()
        append("记住网关名：\\(name)（下次直接用它）")
    }

    private func persist() {'''
if anchor not in s:
    raise SystemExit("锚点 G 没找到")
s = s.replace(anchor, helper, 1)

io.open(STORE, "w", encoding="utf-8", newline="\n").write(s)
print("AppStore patched")
