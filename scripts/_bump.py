# -*- coding: utf-8 -*-
"""把 project.yml 里的版本号从 old 改成 new（四处字段一起改）。"""
import io
import sys

path = r"C:\Users\Chen\Documents\deepseek-harness\default-workspace\giwifi-ios\project.yml"
old_ver, new_ver, old_build, new_build = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

text = io.open(path, encoding="utf-8").read()
before = text
text = text.replace('MARKETING_VERSION: "%s"' % old_ver, 'MARKETING_VERSION: "%s"' % new_ver)
text = text.replace('CURRENT_PROJECT_VERSION: "%s"' % old_build, 'CURRENT_PROJECT_VERSION: "%s"' % new_build)
text = text.replace('CFBundleShortVersionString: "%s"' % old_ver, 'CFBundleShortVersionString: "%s"' % new_ver)
text = text.replace('CFBundleVersion: "%s"' % old_build, 'CFBundleVersion: "%s"' % new_build)

if text == before:
    print("没有变化，检查参数")
else:
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)
    print("bumped %s (%s) -> %s (%s)" % (old_ver, old_build, new_ver, new_build))
for line in text.splitlines():
    if "VERSION" in line or "CFBundleShortVersionString" in line or "CFBundleVersion" in line:
        print("  " + line.strip())
