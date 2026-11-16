import re
import urllib.request

PORTAL = "http://100.100.9.2/gportal/web/login"
UAS = {
    "curl": "curl/8.0",
    "chrome-win": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    "iphone-safari": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
    "android": "Mozilla/5.0 (Linux; Android 14; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
    "okhttp": "okhttp/3.8.0",
    "captive": "CaptiveNetworkSupport-420.10.4 wispr",
}
PATTERNS = [
    r"wlanacname=([A-Za-z0-9\-_]+)",
    r'"nasName"\s*:\s*"([^"]+)"',
    r"nasName=([A-Za-z0-9\-_]+)",
    r"GiWiFi_[A-Za-z0-9_]+",
]

for name, ua in UAS.items():
    req = urllib.request.Request(PORTAL, headers={"User-Agent": ua, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            body = resp.read()
            text = body.decode("utf-8", "ignore")
            hits = []
            for p in PATTERNS:
                hits += re.findall(p, text)
            print(f"{name:14s} HTTP {resp.status} bytes={len(body)} final={resp.geturl()} hits={hits[:5]}")
    except urllib.error.HTTPError as exc:
        body = exc.read()
        print(f"{name:14s} HTTP {exc.code} bytes={len(body)} {body[:120]!r}")
    except Exception as exc:  # noqa: BLE001
        print(f"{name:14s} ERR {exc}")
