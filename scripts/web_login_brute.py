"""在 ac 字段来源不明时做一轮组合探测。

判定：响应 info 不再是 "ac is empty" 就算命中（说明 ac 被服务端认出来了）。
"""
from __future__ import annotations

import base64
import http.cookiejar
import io
import json
import re
import ssl
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, __file__.rsplit("\\", 1)[0])
from probe_portal import aes_encrypt, local_ip  # noqa: E402
from web_login_probe import AES_KEY, LOGIN_ACTION, LOGIN_PAGE, UA, cbc_encrypt_b64, parse_form, serialize, zero_pad  # noqa: E402

PORTAL = "http://100.100.9.2"
USER = "17830530307"
PASSWORD = "test123456"
AC_CANDIDATES = ["GiWiFi_lnsfHG", "GiWiFi_lnsf", "1", "0", "2", "default", "hgh"]


def build_opener() -> tuple[urllib.request.OpenerDirector, http.cookiejar.CookieJar]:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPCookieProcessor(jar),
        urllib.request.HTTPSHandler(context=ctx),
    )
    return opener, jar


def fetch_page(opener, url: str, ua: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": ua, "Accept": "text/html,*/*"})
    with opener.open(req, timeout=15) as resp:
        return resp.read().decode("utf-8", "replace")


def submit(opener, ua: str, body: bytes, extra_headers: dict[str, str]) -> str:
    headers = {
        "User-Agent": ua,
        "Content-Type": "application/json;charset=UTF-8",
        "Accept": "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With": "XMLHttpRequest",
        "Origin": PORTAL,
        "Referer": PORTAL + LOGIN_PAGE,
    }
    headers.update(extra_headers)
    req = urllib.request.Request(PORTAL + LOGIN_ACTION, data=body, method="POST", headers=headers)
    try:
        with opener.open(req, timeout=25) as resp:
            return resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.read().decode("utf-8", "replace")


def attempt(label: str, *, query: dict[str, str] | None = None,
            extra_field: str = "", cookie: str = "", header: dict[str, str] | None = None,
            page_query: dict[str, str] | None = None) -> str:
    opener, jar = build_opener()
    ua = UA["ipad"]
    url = PORTAL + LOGIN_PAGE
    if page_query:
        url += "?" + urllib.parse.urlencode(page_query)
    html = fetch_page(opener, url, ua)
    pairs, iv = parse_form(html)
    merged = [(k, v) for k, v in pairs if k not in ("user_account", "user_password")]
    merged.append(("user_account", USER))
    merged.append(("user_password", PASSWORD))
    plain = serialize(merged)
    if extra_field:
        plain += "&" + extra_field
    body = json.dumps({"data": cbc_encrypt_b64(plain, AES_KEY, iv), "iv": iv}).encode()
    if cookie:
        for part in cookie.split(";"):
            if "=" in part:
                k, v = part.split("=", 1)
                jar.set_cookie(http.cookiejar.Cookie(
                    0, k.strip(), v.strip(), None, False, "100.100.9.2", False, False,
                    "/", True, False, None, False, None, None, {}))
    text = submit(opener, ua, body, header or {})
    ok = "ac is empty" not in text
    print("%-46s %s  %s" % (label, "HIT " if ok else "miss", text[:160]))
    return text if ok else ""


def main() -> int:
    ua = UA["ipad"]
    attempts = 0

    for cand in AC_CANDIDATES:
        if attempt("post ac=%s" % cand, extra_field="ac=" + urllib.parse.quote_plus(cand)):
            return 0
        attempts += 1
    for cand in AC_CANDIDATES:
        if attempt("page ?ac=%s" % cand, page_query={"ac": cand}):
            return 0
        attempts += 1
    for cand in AC_CANDIDATES:
        if attempt("query ?ac=%s" % cand, query={"ac": cand}):
            return 0
        attempts += 1
    for cand in AC_CANDIDATES:
        if attempt("cookie ac=%s" % cand, cookie="ac=" + cand):
            return 0
        attempts += 1
    for cand in AC_CANDIDATES:
        if attempt("header ac=%s" % cand, header={"ac": cand}):
            return 0
        attempts += 1
    for cand in ["wlanacname", "nasname", "acname", "ac_name", "accessController"]:
        if attempt("post %s=%s" % (cand, AC_CANDIDATES[0]),
                   extra_field="%s=%s" % (cand, urllib.parse.quote_plus(AC_CANDIDATES[0]))):
            return 0
        attempts += 1

    print("全部 %d 种组合都是 ac is empty" % attempts)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
