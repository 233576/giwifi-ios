#!/usr/bin/env python3
"""在校园网内直接复现 GiWiFi Portal 请求，用于排查认证失败。

用法：
    python scripts/probe_portal.py --user 18933391993 [--pass 密码] [--ip 10.13.10.185]

不传密码时只做 queryAuthState（不需要密码），能拿到网关看到的 MAC / authState。
AES-128 用纯 Python 实现，避免依赖 pycryptodome。
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import socket
import struct
import sys
import time
import urllib.parse
import urllib.request

# ---------------------------------------------------------------- AES-128 ECB


def _build_tables():
    def gmul(a: int, b: int) -> int:
        p = 0
        for _ in range(8):
            if b & 1:
                p ^= a
            hi = a & 0x80
            a = (a << 1) & 0xFF
            if hi:
                a ^= 0x1B
            b >>= 1
        return p

    inv = [0] * 256
    for x in range(1, 256):
        for y in range(1, 256):
            if gmul(x, y) == 1:
                inv[x] = y
                break

    def rotl8(x: int, shift: int) -> int:
        return ((x << shift) | (x >> (8 - shift))) & 0xFF

    sbox = [0] * 256
    for x in range(256):
        b = inv[x]
        s = b
        for i in range(1, 5):
            s ^= rotl8(b, i)
        sbox[x] = s ^ 0x63

    inv_sbox = [0] * 256
    for i, v in enumerate(sbox):
        inv_sbox[v] = i
    return sbox, inv_sbox


SBOX, INV_SBOX = _build_tables()
RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]


def _expand_key(key: bytes) -> list[list[int]]:
    assert len(key) == 16
    w = [list(key[i * 4:i * 4 + 4]) for i in range(4)]
    for i in range(4, 44):
        temp = list(w[i - 1])
        if i % 4 == 0:
            temp = temp[1:] + temp[:1]
            temp = [SBOX[b] for b in temp]
            temp[0] ^= RCON[i // 4 - 1]
        w.append([w[i - 4][j] ^ temp[j] for j in range(4)])
    return w


def _add_round_key(state: list[int], w: list[list[int]], rnd: int) -> None:
    for c in range(4):
        for r in range(4):
            state[r + 4 * c] ^= w[rnd * 4 + c][r]


def _encrypt_block(block: bytes, w: list[list[int]]) -> bytes:
    state = list(block)
    _add_round_key(state, w, 0)
    for rnd in range(1, 11):
        state = [SBOX[b] for b in state]
        # ShiftRows（列优先存储：state[r + 4c]）
        shifted = [0] * 16
        for r in range(4):
            for c in range(4):
                shifted[r + 4 * c] = state[r + 4 * ((c + r) % 4)]
        state = shifted
        if rnd != 10:
            mixed = [0] * 16
            for c in range(4):
                col = state[4 * c:4 * c + 4]
                mixed[4 * c + 0] = _gmul2(col[0]) ^ _gmul3(col[1]) ^ col[2] ^ col[3]
                mixed[4 * c + 1] = col[0] ^ _gmul2(col[1]) ^ _gmul3(col[2]) ^ col[3]
                mixed[4 * c + 2] = col[0] ^ col[1] ^ _gmul2(col[2]) ^ _gmul3(col[3])
                mixed[4 * c + 3] = _gmul3(col[0]) ^ col[1] ^ col[2] ^ _gmul2(col[3])
            state = mixed
        _add_round_key(state, w, rnd)
    return bytes(state)


def _gmul2(a: int) -> int:
    return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else (a << 1) & 0xFF


def _gmul3(a: int) -> int:
    return _gmul2(a) ^ a


def _decrypt_block(block: bytes, w: list[list[int]]) -> bytes:
    state = list(block)
    _add_round_key(state, w, 10)
    for rnd in range(9, -1, -1):
        # InvShiftRows
        shifted = [0] * 16
        for r in range(4):
            for c in range(4):
                shifted[r + 4 * ((c + r) % 4)] = state[r + 4 * c]
        state = [INV_SBOX[b] for b in shifted]
        _add_round_key(state, w, rnd)
        if rnd != 0:
            mixed = [0] * 16
            for c in range(4):
                col = state[4 * c:4 * c + 4]
                mixed[4 * c + 0] = _gmul(col[0], 14) ^ _gmul(col[1], 11) ^ _gmul(col[2], 13) ^ _gmul(col[3], 9)
                mixed[4 * c + 1] = _gmul(col[0], 9) ^ _gmul(col[1], 14) ^ _gmul(col[2], 11) ^ _gmul(col[3], 13)
                mixed[4 * c + 2] = _gmul(col[0], 13) ^ _gmul(col[1], 9) ^ _gmul(col[2], 14) ^ _gmul(col[3], 11)
                mixed[4 * c + 3] = _gmul(col[0], 11) ^ _gmul(col[1], 13) ^ _gmul(col[2], 9) ^ _gmul(col[3], 14)
            state = mixed
    return bytes(state)


def _gmul(a: int, b: int) -> int:
    p = 0
    for _ in range(8):
        if b & 1:
            p ^= a
        hi = a & 0x80
        a = (a << 1) & 0xFF
        if hi:
            a ^= 0x1B
        b >>= 1
    return p


def aes_encrypt(plaintext: bytes, key: bytes) -> bytes:
    pad = 16 - len(plaintext) % 16
    padded = plaintext + bytes([pad]) * pad
    w = _expand_key(key)
    return b"".join(_encrypt_block(padded[i:i + 16], w) for i in range(0, len(padded), 16))


def aes_decrypt(ciphertext: bytes, key: bytes) -> bytes:
    w = _expand_key(key)
    out = b"".join(_decrypt_block(ciphertext[i:i + 16], w)
                   for i in range(0, len(ciphertext), 16))
    if not out:
        return b""
    pad = out[-1]
    return out[:-pad] if 0 < pad <= 16 else out


def _self_test() -> None:
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    plain = bytes.fromhex("00112233445566778899aabbccddeeff")
    expect = bytes.fromhex("69c4e0d86a7b0430d8cdb78070b4c55a")
    got = _encrypt_block(plain, _expand_key(key))
    assert got == expect, f"AES self-test failed: {got.hex()}"
    assert _decrypt_block(got, _expand_key(key)) == plain


# ---------------------------------------------------------------- 协议

AES_KEY = b"5447c08b53e8dac4"
SIGN_SECRET = "5447c08b53e8dac47f81269f98cfeada"
UA = "okhttp/3.8.0"


def java_form_encode(value: str) -> str:
    out = []
    for ch in value:
        if ch.isalnum() and ch.isascii() or ch in "-_.*":
            out.append(ch)
        elif ch == " ":
            out.append("+")
        else:
            for byte in ch.encode("utf-8"):
                out.append("%%%02X" % byte)
    return "".join(out)


def signed_payload(fields: dict[str, str], password_field: str | None = None) -> str:
    raw = "&".join(f"{k}={fields[k]}" for k in sorted(fields))
    signature = hashlib.md5((raw + SIGN_SECRET).encode()).hexdigest()
    encoded = dict(fields)
    if password_field and encoded.get(password_field) is not None:
        encoded[password_field] = java_form_encode(encoded[password_field])
    body = "&".join(f"{k}={encoded[k]}" for k in sorted(encoded))
    return body + "&sign=" + signature


def encode_data(plaintext: str) -> str:
    b64 = base64.b64encode(aes_encrypt(plaintext.encode(), AES_KEY)).decode()
    return java_form_encode(b64)


def decode_data(value: str) -> str:
    raw = urllib.parse.unquote_plus(value)
    return aes_decrypt(base64.b64decode(raw), AES_KEY).decode("utf-8", "replace")


def post(portal: str, path: str, fields: dict[str, str],
         password_field: str | None = None) -> tuple[int, str]:
    payload = signed_payload(fields, password_field)
    body = ("data=" + java_form_encode(encode_data(payload))).encode()
    req = urllib.request.Request(
        portal.rstrip("/") + path,
        data=body,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Connection": "Keep-Alive",
            "User-Agent": UA,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


def show(label: str, status: int, body: str) -> dict | None:
    print(f"\n== {label} == HTTP {status}")
    try:
        obj = json.loads(body)
    except Exception:
        print(body[:400])
        return None
    print("raw:", json.dumps(obj, ensure_ascii=False)[:400])
    data = obj.get("data")
    if isinstance(data, str) and data and not data.strip().startswith("{"):
        try:
            plain = decode_data(data)
            print("decrypted data:", plain[:800])
            try:
                return json.loads(plain)
            except Exception:
                return None
        except Exception as exc:
            print("decrypt failed:", exc)
    elif isinstance(data, dict):
        print("data:", json.dumps(data, ensure_ascii=False)[:800])
        return data
    return None


def local_ip() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("100.100.9.2", 80))
        return sock.getsockname()[0]
    finally:
        sock.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--portal", default="http://100.100.9.2/gportal/web/login")
    parser.add_argument("--user", required=True)
    parser.add_argument("--pass", dest="password", default="")
    parser.add_argument("--ip", default="")
    parser.add_argument("--app-uuid", default="")
    parser.add_argument("--nas", default="GiWiFi_lnsfHG")
    parser.add_argument("--mac", default="")
    args = parser.parse_args()

    _self_test()
    origin = args.portal.split("/gportal")[0]
    ip = args.ip or local_ip()
    app_uuid = args.app_uuid or "56a05633-59ca-464b-807fb1ff4918829e"
    print(f"portal={origin} ip={ip} user={args.user} uuid={app_uuid}")

    # 1. 首页：看 nasName / MAC 是否能拿到
    try:
        req = urllib.request.Request(origin + "/gportal/web/login",
                                     headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            html = resp.read().decode("utf-8", "replace")
            print(f"\n== GET /gportal/web/login == HTTP {resp.status} "
                  f"final={resp.geturl()} bytes={len(html)}")
            for key in ("wlanacname", "nasName", "userMac", "staMac", "clientMac"):
                idx = html.lower().find(key.lower())
                if idx >= 0:
                    print(f"  {key} @ {idx}: {html[max(0,idx-60):idx+90]!r}")
    except Exception as exc:
        print("GET 首页失败：", exc)

    # 2. 状态查询（不需要密码）
    state, body = post(origin, "/gportal/app/queryAuthState", {
        "timestamp": str(int(time.time())),
        "userIp": ip,
        "userName": args.user,
    })
    show("queryAuthState", state, body)

    # 3. 认证（有密码才做）
    if args.password:
        ts = str(int(time.time()))
        fields = {
            "appUuid": app_uuid,
            "userIp": ip,
            "nasName": args.nas,
            "ssid": "",
            "nasIp": "",
            "vlan": "1",
            "apMac": "",
            "userFirstUrl": "",
            "userName": args.user,
            "passwd": args.password,
            "btype": "2",
            "staType": "pad",
            "staModel": "samsung,SM-T870,34,14",
            "timestamp": ts,
        }
        state, body = post(origin, "/gportal/app/authLogin", fields, "passwd")
        show("authLogin(no mac)", state, body)

        time.sleep(6)
        fields["timestamp"] = str(int(time.time()))
        fields["userMac"] = args.mac or "4c:a9:54:4b:cc:01"
        state, body = post(origin, "/gportal/app/authLogin", fields, "passwd")
        show("authLogin(with mac)", state, body)
    else:
        print("\n（没给 --pass，跳过 authLogin）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
