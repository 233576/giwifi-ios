import io
import re

P = r"C:\Users\Chen\Desktop\giwifi_ua_switcher-1.1.6-windows-x64\data\app.so"
data = io.open(P, "rb").read()
print("size", len(data))

needles = [b"user_account", b"user_password", b"loginAction", b"account_type",
           b"login_type", b"action_type", b"request_ip", b"sta_ip", b"nas_ip",
           b"nas_name", b"device_mode", b"device_type", b"is_mobile", b"iv",
           b"=ac&", b"ac=", b"&ac", b"hidden", b"sign"]

for n in needles:
    hits = [m.start() for m in re.finditer(re.escape(n), data)]
    print("%-16s %d" % (n.decode(), len(hits)))
    for h in hits[:3]:
        frag = data[max(0, h - 90):h + 110]
        txt = "".join(chr(b) if 32 <= b < 127 else "." for b in frag)
        print("     ", txt)

print("==== 所有 xxx=x& 形式的串（疑似字段名） ====")
seen = set()
for m in re.finditer(rb"[A-Za-z_][A-Za-z0-9_]{2,20}=", data):
    s = m.group(0)[:-1].decode()
    if s in seen:
        continue
    seen.add(s)
print(" ".join(sorted(seen))[:3000])
