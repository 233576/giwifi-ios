# -*- coding: utf-8 -*-
"""两处修复：
1) nasName 重试不再无条件等 5 秒，只有 102 / 频繁 才等。
2) nasName 重试拿到 43 时，把 needsRebind / bindPath 带出去（原来丢了，
   导致 App 里 rebindPath 永远为空，点「换绑到本机」只能走 reBindMac）。
"""
import io

CLIENT = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\Sources\Core\GiWifiClient.swift"

text = io.open(CLIENT, encoding="utf-8").read()
orig = text

old_retry_head = '''                    log("认证被拒（\\(firstAuth.message)），改用 nasName=\\(candidate) 重试（等 5 秒避开频率限制）")
                    try? await Task.sleep(nanoseconds: 5_200_000_000)'''
new_retry_head = '''                    let throttled = firstAuth.resultCode == 102 || firstAuth.message.contains("频繁")
                    log("认证被拒（\\(firstAuth.message)），改用 nasName=\\(candidate) 重试\\(throttled ? "（等 5 秒避开频率限制）" : "")")
                    if throttled { try? await Task.sleep(nanoseconds: 5_200_000_000) }'''

if old_retry_head not in text:
    raise SystemExit("补丁 1 锚点没找到")
text = text.replace(old_retry_head, new_retry_head)

old_ret = '''                    if let retry, !Self.isChallengeDenied(retry) {
                        return Result(online: false,
                                      message: Self.guidance(for: retry),
                                      portalOrigin: retryContext.portal.absoluteString,
                                      serverMac: retryContext.userMac,
                                      authState: retry.authState,
                                      needsProfile: Self.needsProfileCompletion(retry))
                    }'''
new_ret = '''                    if let retry, !Self.isChallengeDenied(retry) {
                        // 43/203 要带出 bindPath，否则上层拿不到换绑链接。
                        return Result(online: false,
                                      message: Self.guidance(for: retry),
                                      portalOrigin: retryContext.portal.absoluteString,
                                      serverMac: retryContext.userMac,
                                      authState: retry.authState,
                                      needsProfile: Self.needsProfileCompletion(retry),
                                      needsRebind: retry.requiresRebind,
                                      bindPath: retry.bindPath)
                    }'''

if old_ret not in text:
    raise SystemExit("补丁 2 锚点没找到")
text = text.replace(old_ret, new_ret)

io.open(CLIENT, "w", encoding="utf-8", newline="\n").write(text)
print("patched GiWifiClient.swift, %d -> %d bytes" % (len(orig.encode()), len(text.encode())))
print("throttled 出现次数:", text.count("let throttled"))
print("needsRebind: retry.requiresRebind 出现次数:", text.count("needsRebind: retry.requiresRebind"))
