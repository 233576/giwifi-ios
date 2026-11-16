"""生成 GiWiFi 助手图标：深青渐变 + 白色 WiFi 弧 + 底部字。"""

import json
import os

from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
OUT_DIR = os.path.join("Sources", "Resources", "Assets.xcassets", "AppIcon.appiconset")


def pick_font(size):
    for path in (
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\msyh.ttc",
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def main():
    img = Image.new("RGB", (SIZE, SIZE), (16, 92, 120))
    draw = ImageDraw.Draw(img)

    # 竖向渐变
    top = (18, 104, 136)
    bottom = (6, 32, 66)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (SIZE, y)], fill=color)

    # 极淡网格
    grid = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    g = ImageDraw.Draw(grid)
    for i in range(0, 8):
        x = SIZE * 0.02 + (SIZE * 0.96) * i / 7
        g.line([(x, 0), (x, SIZE)], fill=(255, 255, 255, 18), width=4)
    for j in range(0, 9):
        y = SIZE * 0.02 + (SIZE * 0.96) * j / 8
        g.line([(0, y), (SIZE, y)], fill=(255, 255, 255, 18), width=4)
    img = Image.alpha_composite(img.convert("RGBA"), grid).convert("RGB")
    draw = ImageDraw.Draw(img)

    # WiFi 弧：三段同心圆弧 + 底部圆点
    cx, cy = SIZE * 0.5, SIZE * 0.545
    radii = [SIZE * 0.125, SIZE * 0.215, SIZE * 0.305]
    for radius in radii:
        box = [cx - radius, cy - radius, cx + radius, cy + radius]
        draw.arc(box, start=225, end=315, fill=(255, 255, 255), width=int(SIZE * 0.034))
    dot = SIZE * 0.045
    draw.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(255, 255, 255))

    # 底部文字
    label = "GiWiFi"
    font = pick_font(112)
    bbox = draw.textbbox((0, 0), label, font=font)
    draw.text(((SIZE - (bbox[2] - bbox[0])) / 2 - bbox[0], SIZE * 0.845 - bbox[1]),
              label, font=font, fill=(226, 240, 248))

    os.makedirs(OUT_DIR, exist_ok=True)
    icon_path = os.path.join(OUT_DIR, "icon-1024.png")
    img.save(icon_path)

    contents = {
        "images": [
            {"filename": "icon-1024.png", "idiom": "universal",
             "platform": "ios", "size": "1024x1024"}
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT_DIR, "Contents.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(contents, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print("wrote", icon_path)
    print("wrote Contents.json")


if __name__ == "__main__":
    main()
