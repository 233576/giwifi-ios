# -*- coding: utf-8 -*-
"""login() 里 43 自动换绑：拿到 bindPath 就 GET 一遍，然后重新认证一次。"""
import io

STORE = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\Sources\Core\AppStore.swift"

text = io.open(STORE, encoding="utf-8").read()
orig_len = len(text.encode())

anchor = '''        forceRebind = false
        if result.online {'''

inject = '''        forceRebind = false
        // 43/203：服务端把「确认绑定」的链接放在 data 里，GET 它即完成换绑。
        // 这里自动做一次，再重新认证，用户不必再点按钮（点按钮仍然保留作为兜底）。
        if !result.online, result.needsRebind, !result.bindPath.isEmpty, !autoBindTried {
            autoBindTried = true
            append("服务端要求确认绑定，自动提交：\\(result.bindPath)")
            if let portalURL = URL(string: result.portalOrigin) {
                let ok = await client.completeBind(portal: portalURL,
                                                   path: result.bindPath,
                                                   profile: profile)
                append(ok ? "绑定链接已提交，重新认证…" : "绑定链接提交失败，改走 reBindMac")
            }
            if let retry = await client.login(
                username: settings.username,
                password: settings.password,
                profile: profile,
                appUuid: settings.appUuid,
                serviceType: settings.serviceType,
                allowRebind: true
            ) {
                result = retry
                portal = retry.portalOrigin.isEmpty ? portal : retry.portalOrigin
                if !retry.serverMac.isEmpty { serverMac = retry.serverMac }
            }
        }
        if result.online {'''

if anchor not in text:
    raise SystemExit("锚点没找到")
text = text.replace(anchor, inject, 1)

# 声明 autoBindTried（放在 login 开头，避免每次自动重连都再试）
decl_anchor = '''        let profile = currentProfile
        append("==== \\(auto ? "自动重连" : "开始认证")'''
decl_new = '''        let profile = currentProfile
        var autoBindTried = false
        append("==== \\(auto ? "自动重连" : "开始认证")'''
if decl_anchor in text:
    text = text.replace(decl_anchor, decl_new, 1)
else:
    raise SystemExit("声明锚点没找到")

io.open(STORE, "w", encoding="utf-8", newline="\n").write(text)
print("patched AppStore.swift, %d -> %d bytes" % (orig_len, len(text.encode())))
print("autoBindTried 次数:", text.count("autoBindTried"))
