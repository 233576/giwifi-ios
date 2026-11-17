"""一次性完成：注销 -> 抓网关 302 -> 解析出 ac/wlanacname/wlanuserip -> 带参数登录恢复。

为什么要注销：服务端只有在「被网关拦截」的那一跳里才知道 AC 上下文，
直接访问登录页永远返回 error: ac is empty。

安全措施：不管中间哪一步失败，最后都会用你给的账号密码尝试重新登录，
把网络恢复回来。全程约 3~6 秒。

用法：
    set PYTHONIOENCODING=utf-8
    python scripts\\capture_ac.py --user 17830530307 --pass 你的密码
    python scripts\\capture_ac.py --user ... --pass ... --dry-run   只打印计划不执行
"""
from __future__ import annotations

import argparse
import http.cookiejar
import json
import re
import ssl
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from web_login_probe import (  # noqa: E402
    AES_KEY, LOGIN_ACTION, LOGIN_PAGE, UA, cbc_encrypt_b64, parse_form, serialize,
)

PORTAL = "http://100.100.9.2"
PROBE_HOSTS = ["http://1.1.1.1", "http://connect.rom.miui.com/generate_204",
               "http://www.apple.com/library/test/success.html"]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D102
        return None


def opener_with(jar, follow: bool):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    handlers = [urllib.request.ProxyHandler({}),
                urllib.request.HTTPCookieProcessor(jar),
                urllib.request.HTTPSHandler(context=ctx)]
    if not follow:
        handlers.append(NoRedirect())
    return urllib.request.build_opener(*handlers)


def read_any(opener, url: str, ua: str, headers=None, data: bytes | None = None,
             timeout: int = 8):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": ua, **(headers or {})})
    try:
        with opener.open(req, timeout=timeout) as resp:
            return resp.status, dict(resp.headers), resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace") if exc.fp else ""
        return exc.code, dict(exc.headers), body
    except Exception as exc:  # noqa: BLE001  超时/被重置都算「没抓到」
        return 0, {}, "NETERR: %s" % exc


def portal_login(opener, ua: str, user: str, password: str, query: dict[str, str]) -> str:
    url = PORTAL + LOGIN_PAGE
    if query:
        url += "?" + urllib.parse.urlencode(query)
    _, _, html = read_any(opener, url, ua, timeout=15)
    if 'id="loginForm"' not in html:
        return "FAIL: 登录页没有 loginForm（%d 字节），AC 可能不被认可" % len(html)
    pairs, iv = parse_form(html)
    merged = [(k, v) for k, v in pairs if k not in ("user_account", "user_password")]
    merged.append(("user_account", user))
    merged.append(("user_password", password))
    plain = serialize(merged)
    body = json.dumps({"data": cbc_encrypt_b64(plain, AES_KEY, iv), "iv": iv}).encode()
    code, _, text = read_any(opener, PORTAL + LOGIN_ACTION, ua, {
        "Content-Type": "application/json;charset=UTF-8",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With": "XMLHttpRequest",
        "Origin": PORTAL,
        "Referer": PORTAL + LOGIN_PAGE,
    }, data=body, timeout=20)
    return "HTTP %d %s" % (code, text[:400])


def main() -> int:
    global PORTAL
    ap = argparse.ArgumentParser()
    ap.add_argument("--user", required=True)
    ap.add_argument("--pass", dest="password", required=True)
    ap.add_argument("--portal", default=PORTAL)
    ap.add_argument("--ua", default="ipad", choices=sorted(UA))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    PORTAL = args.portal.rstrip("/")
    ua = UA[args.ua]

    print("0) 预检：确认登录页能打开（拿不到表单就不敢注销，避免把你卡在断网状态）")
    jar0 = http.cookiejar.CookieJar()
    op0 = opener_with(jar0, follow=True)
    code, _, html0 = read_any(op0, PORTAL + LOGIN_PAGE, ua, timeout=15)
    if 'id="loginForm"' not in html0:
        print("   预检失败：登录页 %d 字节，没有 loginForm。已中止，未做任何注销。" % len(html0))
        return 2
    print("   登录页正常（%d 字节），可以继续" % len(html0))

    print("1) 注销当前认证")
    if args.dry_run:
        print("   [dry-run] 只做了预检，不注销、不抓包、不登录。加上真实密码去掉 --dry-run 才会执行。")
        return 0
    else:
        jar = http.cookiejar.CookieJar()
        op = opener_with(jar, follow=True)
        for path in ("/gportal/Web/logoutAction", "/gportal/web/logout"):
            code, _, text = read_any(op, PORTAL + path, ua, timeout=10)
            print("   %-32s HTTP %-3d %s" % (path, code, text[:120].replace("\n", " ")))
            if code == 200:
                break

    print("2) 抓网关重定向（不跟随），找 ac / wlanacname / wlanuserip")
    captured = ""
    jar2 = http.cookiejar.CookieJar()
    op2 = opener_with(jar2, follow=False)
    for host in PROBE_HOSTS:
        code, headers, _ = read_any(op2, host, ua, timeout=8)
        loc = headers.get("Location") or headers.get("location") or ""
        print("   %-46s -> %s %s" % (host, code, loc[:220]))
        if loc:
            captured = loc
            break

    print("3) 解析参数")
    query: dict[str, str] = {}
    if captured:
        qs = urllib.parse.urlparse(captured).query
        for key in ("ac", "wlanacname", "wlanacip", "wlanuserip", "nas_ip", "nasip",
                    "nas_name", "sta_ip", "url", "login_url"):
            vals = urllib.parse.parse_qs(qs).get(key)
            if vals:
                query[key] = vals[0]
        print("   命中：%s" % (query if query else "（重定向里没有这些参数）"))
        print("   完整 Location：%s" % captured)
    else:
        print("   没有拿到重定向（可能已经掉线且网关不返回 302）")

    print("4) 用抓到的参数重新登录，恢复网络")
    if args.dry_run:
        print("   [dry-run] 跳过")
        return 0
    import time
    plans = [query] if query else []
    plans.append({})
    for extra in plans:
        for attempt in range(1, 4):
            jar3 = http.cookiejar.CookieJar()
            op3 = opener_with(jar3, follow=True)
            result = portal_login(op3, ua, args.user, args.password, extra)
            print("   参数 %-22s 第 %d 次 -> %s" % (str(list(extra)[:1] or "无"), attempt, result))
            if '"status":1' in result or "'status': 1" in result:
                print("登录成功，网络应已恢复。")
                return 0
            if "102" in result or "频繁" in result:
                print("   命中频率限制，等 7 秒重试")
                time.sleep(7)
                continue
            break
    print("4) 都没成功，请把上面的输出发给我。若已断网，用手机热点或等 1 分钟后重跑本脚本。")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
