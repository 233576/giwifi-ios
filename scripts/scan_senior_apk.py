"""扫学长安卓工具的 apk：找 ac / wlanacname / loginAction 的真实来源。"""
from __future__ import annotations

import io
import re
import sys
import zipfile

APK = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\inbox\base.apk"

NEEDLES = [b"loginAction", b"wlanacname", b"wlanuserip", b"wlanac", b"gicgi",
           b"100.100.9.2", b"nas_name", b"sta_ip", b"ac=", b"&ac", b"getac",
           b"pagetype", b"logintype", b"is_mobile", b"device_mode", b"user_account",
           b"1234567887654321", b"Giportal"]


def printable(buf: bytes) -> str:
    return "".join(chr(b) if 32 <= b < 127 else "." for b in buf)


def scan(name: str, data: bytes) -> None:
    hits = []
    for n in NEEDLES:
        for m in re.finditer(re.escape(n), data):
            hits.append((n.decode("ascii", "replace"), m.start()))
    if not hits:
        return
    print("\n######## %s  (%d bytes, %d hits) ########" % (name, len(data), len(hits)))
    seen = set()
    for needle, pos in hits:
        bucket = pos // 64
        if (needle, bucket) in seen:
            continue
        seen.add((needle, bucket))
        frag = printable(data[max(0, pos - 110):pos + 130])
        print("  [%-14s @%-9d] %s" % (needle, pos, frag))


def main() -> int:
    with zipfile.ZipFile(APK) as zf:
        names = zf.namelist()
        print("entries:", len(names))
        target = [n for n in names if n.endswith(".dex")
                  or n.endswith("libapp.so") or n.endswith(".so") and "flutter" in n
                  or n.endswith("libflutter.so")]
        for n in target[:20]:
            info = zf.getinfo(n)
            print("  %-50s %d" % (n, info.file_size))
        # 先扫 dex 与 libapp.so
        for n in target:
            if n.endswith(".dex") or n.endswith("libapp.so"):
                with zf.open(n) as fh:
                    data = fh.read()
                scan(n, data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
