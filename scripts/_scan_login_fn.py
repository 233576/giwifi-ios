import io
import re

P = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\portal_live.html"
h = io.open(P, encoding="utf-8", errors="replace").read()

print("==== login( 调用 ====")
for m in re.finditer(r"login\s*\(", h):
    s = max(0, m.start() - 80)
    print("  ", h[s:m.start() + 160].replace("\n", " "))
    print("   ---")

print("==== function login 定义 ====")
i = h.find("function login")
print(h[i:i + 1500] if i >= 0 else "not found")

print("==== account_type 元素 ====")
for m in re.finditer(r"account_type", h):
    s = max(0, m.start() - 120)
    frag = h[s:m.start() + 160].replace("\n", " ")
    print("  ", frag)
    if m.start() > 60000:
        break

print("==== loginBtn / 提交按钮 ====")
for kw in ["loginBtn", "btn_login", "submit", "onclick"]:
    i = h.find(kw)
    print("[%s] %s" % (kw, h[max(0, i - 80):i + 160].replace("\n", " ") if i >= 0 else "none"))
