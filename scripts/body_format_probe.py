# -*- coding: utf-8 -*-
"""对比 /gportal/Web/loginAction 接受的 body 编码：JSON 还是 form-urlencoded。

用同一份页面隐藏域、同一个 iv，只换 Content-Type 与序列化方式，
看服务端回的是「ac is empty」还是「参数错误 / CHALLENGE_ERR_DENY」。
密码用占位值，因为 ac 校验发生在账号校验之前。
"""
import http.cookiejar
import io
import json
import re
import ssl
import sys
import urllib.parse
import urllib.request

PORTAL = "http://100.100.9.2"
LOGIN_PAGE = "/gportal/web/login"
LOGIN_ACTION = "/gportal/Web/loginAction"
AES_KEY = "1234567887654321"
UA = ("Mozilla/5.0 (iPad; CPU OS 18_5 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1")


def _xtime(a, b):
    r = 0
    for _ in range(8):
        if a & 1:
            r ^= b
        hi = b & 0x80
        b = (b << 1) & 0xFF
        if hi:
            b ^= 0x1B
        a >>= 1
    return r


def _build_sbox():
    sbox = [0] * 256
    inv = [0] * 256
    for i in range(256):
        inv[i] = next(x for x in range(256) if _xtime(i, x) == 1) if i else 0
    for i in range(256):
        v = inv[i]
        s = v
        for _ in range(4):
            v = ((v << 1) | (v >> 7)) & 0xFF
            s ^= v
        sbox[i] = s ^ 0x63
    return sbox


SBOX = _build_sbox()


def _expand(key):
    w = [list(key[i * 4:i * 4 + 4]) for i in range(4)]
    rcon = 1
    for i in range(4, 44):
        t = list(w[i - 1])
        if i % 4 == 0:
            t = t[1:] + t[:1]
            t = [SBOX[b] for b in t]
            t[0] ^= rcon
            rcon = _xtime(rcon, 2)
        w.append([w[i - 4][j] ^ t[j] for j in range(4)])
    return [sum(w[i * 4:(i + 1) * 4], []) for i in range(11)]


def _encrypt_block(block, keys):
    s = [block[i] ^ keys[0][i] for i in range(16)]
    for rnd in range(1, 11):
        s = [SBOX[b] for b in s]
        s = [s[(i + (i % 4) * 4) % 16] for i in range(16)]
        if rnd != 10:
            out = []
            for c in range(4):
                col = s[c * 4:c * 4 + 4]
                a0, a1, a2, a3 = col
                out += [
                    _xtime(a0, 2) ^ _xtime(a1, 3) ^ a2 ^ a3,
                    a0 ^ _xtime(a1, 2) ^ _xtime(a2, 3) ^ a3,
                    a0 ^ a1 ^ _xtime(a2, 2) ^ _xtime(a3, 3),
                    _xtime(a0, 3) ^ a1 ^ a2 ^ _xtime(a3, 2),
                ]
            s = out
        s = [s[i] ^ keys[rnd][i] for i in range(16)]
    return s


def encrypt_b64(text, key, iv):
    raw = text.encode("utf-8")
    if len(raw) % 16:
        raw += b"\x00" * (16 - len(raw) % 16)
    keys = _expand(key.encode("utf-8"))
    prev = list(iv.encode("utf-8"))
    out = bytearray()
    for i in range(0, len(raw), 16):
        blk = [raw[i + j] ^ prev[j] for j in range(16)]
        enc = _encrypt_block(blk, keys)
        out += bytes(enc)
        prev = enc
    import base64
    return base64.b64encode(bytes(out)).decode()


def serialize(pairs):
    return "&".join("%s=%s" % (urllib.parse.quote_plus(k, safe="-_.*"),
                               urllib.parse.quote_plus(v, safe="-_.*"))
                    for k, v in pairs)


def read(opener, url, data=None, headers=None, timeout=20):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method="POST" if data else "GET")
    try:
        with opener.open(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        return 0, "NETERR: %s" % exc


def main():
    ctx = ssl._create_unverified_context()
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPCookieProcessor(jar),
        urllib.request.HTTPSHandler(context=ctx),
    )
    code, html = read(opener, PORTAL + LOGIN_PAGE, headers={"User-Agent": UA})
    print("GET 登录页 -> %d, %d 字节" % (code, len(html)))
    i = html.find('id="loginForm"')
    j = html.find("</form>", i)
    frag = html[i:j]
    pairs, iv = [], ""
    for tag in re.findall(r"<input[^>]*>", frag, re.S):
        if 'type="hidden"' not in tag:
            continue
        name = re.search(r'name="([^"]*)"', tag)
        value = re.search(r'value="([^"]*)"', tag)
        if not name:
            continue
        v = value.group(1) if value else ""
        if name.group(1) == "iv":
            iv = v
        pairs.append((name.group(1), v))
    print("隐藏域 %d 个, iv=%s" % (len(pairs), iv))
    if not iv:
        print("没拿到 iv，退出")
        return 1

    merged = [(k, v) for k, v in pairs if k not in ("user_account", "user_password")]
    merged.append(("user_account", "17830530307"))
    merged.append(("user_password", "placeholder-not-real"))
    plain = serialize(merged)
    cipher = encrypt_b64(plain, AES_KEY, iv)
    print("密文长度 %d" % len(cipher))

    variants = [
        ("JSON  + application/json",
         json.dumps({"data": cipher, "iv": iv}).encode(),
         "application/json;charset=UTF-8"),
        ("FORM + x-www-form-urlencoded",
         ("data=%s&iv=%s" % (urllib.parse.quote_plus(cipher, safe="-_.*"),
                             urllib.parse.quote_plus(iv, safe="-_.*"))).encode(),
         "application/x-www-form-urlencoded; charset=UTF-8"),
    ]
    for label, body, ctype in variants:
        headers = {
            "User-Agent": UA,
            "Content-Type": ctype,
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": PORTAL,
            "Referer": PORTAL + LOGIN_PAGE,
        }
        code2, text = read(opener, PORTAL + LOGIN_ACTION, data=body, headers=headers)
        print("\n[%s] HTTP %d" % (label, code2))
        print("   " + text[:300].replace("\n", " "))
    return 0


if __name__ == "__main__":
    sys.exit(main())
