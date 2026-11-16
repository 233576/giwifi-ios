import re
import urllib.request

PORTAL = "http://100.100.9.2/gportal/web/login"
UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1")

req = urllib.request.Request(PORTAL, headers={"User-Agent": UA})
with urllib.request.urlopen(req, timeout=10) as resp:
    html = resp.read().decode("utf-8", "ignore")

open("portal_page.html", "w", encoding="utf-8").write(html)
print("saved", len(html), "bytes")

for key in ["nasName", "wlanacname", "GiWiFi_", "userMac", "staMac", "acName", "AC_NAME"]:
    hits = [m.start() for m in re.finditer(key, html)]
    print(f"{key:12s} x{len(hits)}")
    for pos in hits[:3]:
        print("   ...", html[max(0, pos - 90):pos + 90].replace("\n", " ").replace("\r", " "))
