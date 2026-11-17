import io
import re

P = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\portal_live.html"
h = io.open(P, encoding="utf-8", errors="replace").read()
print("len", len(h))

for kw in ["ac=", "&ac", "\"ac\"", "'ac'", "wlanacname", "wlanAcName", "nas_ip"]:
    idx = h.find(kw)
    print("=== %-14s at %s" % (kw, idx))
    if idx >= 0:
        print("    ", h[max(0, idx - 100):idx + 120].replace("\n", " "))

print("---- var assignments ----")
seen = set()
for m in re.finditer(r"var\s+(\w+)\s*=\s*([^;\n]{0,140});", h):
    key = m.group(1)
    if key in seen:
        continue
    seen.add(key)
    print("%-18s = %s" % (key, m.group(2).strip()[:140]))

print("---- form inputs ----")
start = h.find('id="loginForm"')
end = h.find("</form>", start)
for tag in re.findall(r"<input\b[^>]*>", h[start:end], re.I):
    print("   ", " ".join(tag.split())[:160])
