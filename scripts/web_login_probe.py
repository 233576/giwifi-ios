"""复现官方网页表单登录（/gportal/Web/loginAction），用来定位 App 侧失败原因。

用法：
    set PYTHONIOENCODING=utf-8
    python scripts\\web_login_probe.py --user 17830530307 --pass 你的密码
    python scripts\\web_login_probe.py --user ... --pass ... --ua ipad|iphone|android|pc
"""
from __future__ import annotations

import argparse
import base64
import http.cookiejar
import json
import re
import ssl
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from probe_portal import aes_encrypt, local_ip  # noqa: E402

PORTAL = "http://100.100.9.2"
LOGIN_PAGE = "/gportal/web/login"
LOGIN_ACTION = "/gportal/Web/loginAction"
AES_KEY = b"1234567887654321"

UA = {
    "ipad": "Mozilla/5.0 (iPad; CPU OS 18_5 like Mac OS X) AppleWebKit/605.1.15 "
            "(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1",
    "iphone": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 "
              "(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1",
    "android": "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 "
               "(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
    "pc": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
}


def zero_pad(data: bytes) -> bytes:
    rem = len(data) % 16
    if rem == 0:
        return data
    return data + b"\x00" * (16 - rem)


def cbc_encrypt_b64(plaintext: str, key: bytes, iv: str) -> str:
    raw = zero_pad(plaintext.encode("utf-8"))
    prev = iv.encode("utf-8")
    if len(prev) != 16:
        raise ValueError("iv 必须是 16 字节，实际 %d" % len(prev))
    out = b""
    for i in range(0, len(raw), 16):
        block = bytes(a ^ b for a, b in zip(raw[i:i + 16], prev))
        enc = aes_encrypt(block, key)
        out += enc
        prev = enc
    return base64.b64encode(out).decode("ascii")


def parse_form(html: str) -> tuple[list[tuple[str, str]], str]:
    start = html.find('id="loginForm"')
    if start < 0:
        start = html.find("id='loginForm'")
    if start < 0:
        raise RuntimeError("页面里找不到 loginForm")
    end = html.find("</form>", start)
    form = html[start:end]
    pairs: list[tuple[str, str]] = []
    for tag in re.findall(r"<input\b[^>]*>", form, re.I):
        name = re.search(r'name="([^"]*)"', tag) or re.search(r"name='([^']*)'", tag)
        if not name:
            continue
        value = re.search(r'value="([^"]*)"', tag) or re.search(r"value='([^']*)'", tag)
        pairs.append((name.group(1), value.group(1) if value else ""))
    iv = dict(pairs).get("iv", "")
    return pairs, iv


def serialize(pairs: list[tuple[str, str]]) -> str:
    def enc(v: str) -> str:
        return urllib.parse.quote_plus(v, safe="-_.*")
    return "&".join("%s=%s" % (k, enc(v)) for k, v in pairs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--user", required=True)
    ap.add_argument("--pass", dest="password", required=True)
    ap.add_argument("--portal", default=PORTAL)
    ap.add_argument("--ua", default="ipad", choices=sorted(UA))
    ap.add_argument("--no-cookie", action="store_true", help="故意不带 cookie，测试是否为原因")
    ap.add_argument("--dump", action="store_true", help="打印完整表单字段")
    ap.add_argument("--ac", default="", help="wlanacname，AC 名，如 GiWiFi_lnsfHG")
    ap.add_argument("--portal-ip", default="", help="wlanuserip，本机 IP（默认自动探测）")
    ap.add_argument("--extra", default="", help="追加到加密明文的原始串，如 'ac=GiWiFi_lnsfHG'")
    ap.add_argument("--acip", default="", help="wlanacip，AC 的 IP（会填进 nas_ip）")
    args = ap.parse_args()

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar),
        urllib.request.HTTPSHandler(context=ctx),
    )
    ua = UA[args.ua]

    query = [("is_mobile", "1"), ("pagetype", "login"), ("logintype", "1")]
    if args.ac:
        query.append(("wlanacname", args.ac))
    if args.portal_ip or args.ac:
        query.append(("wlanuserip", args.portal_ip or local_ip()))
    if args.acip:
        query.append(("wlanacip", args.acip))
    page_url = LOGIN_PAGE
    if args.ac or args.portal_ip or args.acip:
        page_url = LOGIN_PAGE + "?" + urllib.parse.urlencode(query)
        print("查询串：%s" % page_url.split("?", 1)[1])

    req = urllib.request.Request(args.portal + page_url, headers={
        "User-Agent": ua,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9",
    })
    with opener.open(req, timeout=15) as resp:
        html = resp.read().decode("utf-8", "replace")
        print("GET %s -> %d, %d bytes" % (page_url, resp.status, len(html)))
    print("cookies: %s" % ", ".join("%s=%s" % (c.name, c.value[:12]) for c in jar))

    pairs, iv = parse_form(html)
    print("表单字段 %d 个，iv=%s" % (len(pairs), iv))
    if args.dump:
        for k, v in pairs:
            print("   %-16s = %s" % (k, v[:60]))

    # 账号密码替换 / 追加（保持 jQuery serialize 的顺序语义：input 在 form 末尾）
    merged = [(k, v) for k, v in pairs if k not in ("user_account", "user_password")]
    merged.append(("user_account", args.user))
    merged.append(("user_password", args.password))
    plain = serialize(merged)
    if args.extra:
        plain = plain + "&" + args.extra.strip().lstrip("&")
        print("追加字段：%s" % args.extra)
    print("明文字段数 %d，长度 %d" % (len(merged), len(plain)))
    print("明文（密码已遮蔽）：%s" % plain.replace(
        "user_password=" + urllib.parse.quote_plus(args.password, safe="-_.*"), "user_password=***"))

    body = json.dumps({
        "data": cbc_encrypt_b64(plain, AES_KEY, iv),
        "iv": iv,
    }).encode("utf-8")

    if args.no_cookie:
        jar.clear()

    req2 = urllib.request.Request(args.portal + LOGIN_ACTION, data=body, method="POST", headers={
        "User-Agent": ua,
        "Content-Type": "application/json;charset=UTF-8",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With": "XMLHttpRequest",
        "Origin": args.portal,
        "Referer": args.portal + LOGIN_PAGE,
        "Accept-Language": "zh-CN,zh;q=0.9",
    })
    try:
        with opener.open(req2, timeout=25) as resp:
            text = resp.read().decode("utf-8", "replace")
            print("POST %s -> %d" % (LOGIN_ACTION, resp.status))
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", "replace")
        print("POST %s -> HTTP %d" % (LOGIN_ACTION, exc.code))
    print("响应：%s" % text[:1200])
    try:
        obj = json.loads(text)
        print("RESULT=%r|%r" % (obj.get("status"), obj.get("info")))
        data = obj.get("data")
        if isinstance(data, dict):
            for key in ("resultCode", "resultData", "resultMsg"):
                if key in data:
                    print("  %s = %r" % (key, data[key]))
    except Exception as exc:  # noqa: BLE001
        print("（不是 JSON：%s）" % exc)
        print("RESULT=NONJSON|%s" % text[:80].replace("\n", " "))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
