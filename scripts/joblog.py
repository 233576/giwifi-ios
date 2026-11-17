# -*- coding: utf-8 -*-
"""拉某次 run 的 job 日志（S3 302 不接受 Authorization，手动跟）。"""
import io
import json
import os
import sys
import urllib.request

TOKEN = os.environ["ZF_GITHUB_TOKEN"]
REPO = "233576/giwifi-ios"
RUN = sys.argv[1] if len(sys.argv) > 1 else ""
OUT = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\build.log"

API = "https://api.github.com"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def api_get(url):
    req = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
        "User-Agent": "zf",
    })
    with urllib.request.urlopen(req, timeout=90) as resp:
        return resp.read().decode("utf-8", "replace")


def main():
    jobs = json.loads(api_get("%s/repos/%s/actions/runs/%s/jobs" % (API, REPO, RUN)))
    for job in jobs.get("jobs", []):
        print("job %s -> %s" % (job["name"], job["conclusion"]))
        failed = [s["name"] for s in job.get("steps", []) if s.get("conclusion") == "failure"]
        print("  失败步骤: %s" % (failed or "无"))
        url = "%s/repos/%s/actions/jobs/%s/logs" % (API, REPO, job["id"])
        opener = urllib.request.build_opener(NoRedirect)
        req = urllib.request.Request(url, headers={
            "Authorization": "Bearer " + TOKEN,
            "Accept": "application/vnd.github+json",
            "User-Agent": "zf",
        })
        try:
            resp = opener.open(req, timeout=90)
            text = resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            if exc.code in (301, 302, 303, 307):
                location = exc.headers.get("Location")
                with urllib.request.urlopen(location, timeout=120) as blob:
                    text = blob.read().decode("utf-8", "replace")
            else:
                print("   日志下载失败 HTTP %d" % exc.code)
                continue
        io.open(OUT, "w", encoding="utf-8", newline="\n").write(text)
        print("   日志 %d 字节 -> %s" % (len(text), OUT))
        errs = [line for line in text.splitlines() if "error:" in line]
        for line in errs[:20]:
            print("   ! " + line.strip())
        if not errs:
            print("   （没有 error: 行，尾部 12 行如下）")
            for line in text.splitlines()[-12:]:
                print("   | " + line.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
