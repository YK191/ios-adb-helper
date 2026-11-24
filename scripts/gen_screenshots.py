#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate clean UI preview images for the GitHub README.

The images follow the shipped SwiftUI layout and AppTheme palette. They are
illustrations of the real screens (this environment has no iOS device to
capture from), not modified copies of bug-report screenshots.
"""
import os
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "screenshots")
os.makedirs(OUT, exist_ok=True)

W, H = 390, 844
MINT = (52, 216, 190)
BLUE = (58, 167, 242)
INK = (11, 27, 43)
DANGER = (229, 83, 75)
ORANGE = (255, 169, 90)
TEXT = (28, 38, 48)
SUB = (120, 134, 148)
CARD = (255, 255, 255)
BORDER = (232, 239, 244)

FONT_REG = "C:/Windows/Fonts/msyh.ttc"
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"


def font(size, bold=False):
    path = FONT_BOLD if bold else FONT_REG
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def vgradient(top, bottom, height=H):
    img = Image.new("RGB", (W, height))
    px = img.load()
    for y in range(height):
        t = y / max(1, height - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(W):
            px[x, y] = c
    return img


def shadow_card(d, box, radius=16, fill=CARD, outline=BORDER, shadow=10):
    x0, y0, x1, y1 = box
    d.rounded_rectangle((x0, y0 + 3, x1, y1 + 3), radius=radius, fill=(224, 232, 238))
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=1)


def text(d, xy, s, size=13, color=TEXT, bold=False, anchor=None):
    d.text(xy, s, font=font(size, bold), fill=color, anchor=anchor)


def pill(d, box, label, fg=MINT, bg=(230, 249, 245)):
    d.rounded_rectangle(box, radius=13, fill=bg)
    cx = (box[0] + box[2]) // 2
    cy = (box[1] + box[3]) // 2
    text(d, (cx, cy), label, 11, fg, True, "mm")


def section(d, y, title, subtitle, tint=MINT, icon="square"):
    d.rounded_rectangle((20, y, 50, y + 30), radius=9, fill=tint)
    if icon == "link":
        d.ellipse((28, y + 10, 36, y + 18), outline=(255, 255, 255), width=2)
    elif icon == "folder":
        d.rectangle((27, y + 12, 43, y + 21), fill=(255, 255, 255))
    elif icon == "bolt":
        d.polygon([(35, y + 7), (29, y + 17), (35, y + 16), (32, y + 24), (42, y + 13), (36, y + 14)], fill=(255, 255, 255))
    elif icon == "gear":
        d.ellipse((27, y + 8, 43, y + 24), outline=(255, 255, 255), width=3)
    elif icon == "display":
        d.rectangle((26, y + 9, 44, y + 22), outline=(255, 255, 255), width=2)
    else:
        d.rectangle((28, y + 10, 42, y + 20), outline=(255, 255, 255), width=2)
    text(d, (58, y + 1), title, 15, TEXT, True)
    if subtitle:
        text(d, (58, y + 20), subtitle, 10, SUB)


def status_bar(d, time="13:49"):
    text(d, (22, 11), time, 13, TEXT, True)
    # signal
    for i, h in enumerate((4, 7, 10, 13)):
        d.rounded_rectangle((300 + i * 5, 24 - h, 303 + i * 5, 24), radius=1, fill=TEXT)
    text(d, (324, 10), "4G", 11, TEXT, True)
    # battery
    d.rounded_rectangle((347, 11, 369, 23), radius=4, outline=TEXT, width=1)
    d.rounded_rectangle((349, 13, 363, 21), radius=2, fill=TEXT)
    text(d, (371, 12), "", 8)


def tab_bar(d, active):
    d.rounded_rectangle((18, 770, 372, 826), radius=28, fill=(255, 255, 255), outline=BORDER, width=1)
    labels = ["设备", "终端", "应用", "文件", "设置"]
    for i, label in enumerate(labels):
        cx = 53 + i * 71
        cy = 790
        col = MINT if i == active else (145, 158, 170)
        if i == 0:
            d.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), outline=col, width=2)
            d.line((cx - 4, cy + 4, cx + 4, cy - 4), fill=col, width=2)
        elif i == 1:
            d.rounded_rectangle((cx - 9, cy - 8, cx + 9, cy + 8), radius=3, outline=col, width=2)
            d.line((cx - 5, cy - 3, cx - 1, cy), fill=col, width=2)
            d.line((cx - 1, cy, cx - 5, cy + 3), fill=col, width=2)
            d.line((cx + 1, cy + 3, cx + 6, cy + 3), fill=col, width=2)
        elif i == 2:
            for ox, oy in ((-8, -8), (2, -8), (-8, 2), (2, 2)):
                d.rounded_rectangle((cx + ox, cy + oy, cx + ox + 7, cy + oy + 7), radius=2, fill=col)
        elif i == 3:
            d.polygon([(cx - 9, cy - 5), (cx - 2, cy - 5), (cx, cy - 1), (cx + 9, cy - 1), (cx + 7, cy + 8), (cx - 9, cy + 8)], fill=col)
        else:
            d.ellipse((cx - 8, cy - 8, cx + 8, cy + 8), outline=col, width=3)
            d.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), fill=(255, 255, 255))
        text(d, (cx, cy + 19), label, 10, col, i == active, "mm")
        if i == active:
            d.rounded_rectangle((cx - 16, cy + 31, cx + 16, cy + 34), radius=2, fill=MINT)


def base(active, title, large=True):
    img = vgradient((232, 250, 246), (250, 251, 253))
    d = ImageDraw.Draw(img)
    status_bar(d)
    text(d, (20, 72), title, 30 if large else 20, TEXT, True)
    tab_bar(d, active)
    return img, d


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path, quality=92)
    print(path, os.path.getsize(path))


# ---------------- Device ----------------
def device():
    img, d = base(0, "ADB 助手")
    shadow_card(d, (16, 124, 374, 268))
    d.rounded_rectangle((30, 138, 80, 188), radius=14, fill=MINT)
    d.ellipse((42, 150, 55, 163), outline=(255, 255, 255), width=2)
    d.ellipse((55, 163, 68, 176), outline=(255, 255, 255), width=2)
    d.line((47, 160, 63, 170), fill=(255, 255, 255), width=2)
    text(d, (92, 140), "无线 ADB 连接", 15, TEXT, True)
    text(d, (92, 163), "IP + 端口，需在同一局域网", 10, SUB)
    d.rounded_rectangle((286, 140, 360, 165), radius=12, fill=(231, 249, 245))
    d.ellipse((295, 148, 301, 154), fill=(47, 191, 113))
    text(d, (328, 152), "已连接", 10, (47, 191, 113), True, "mm")
    d.rounded_rectangle((30, 192, 360, 225), radius=10, fill=(247, 250, 252), outline=BORDER)
    text(d, (42, 208), "192.168.1.20", 12, TEXT, False, "lm")
    text(d, (310, 208), ": 5555", 12, SUB, False, "lm")
    d.rounded_rectangle((30, 232, 200, 258), radius=13, fill=MINT)
    text(d, (115, 245), "已连接", 11, (255, 255, 255), True, "mm")
    d.rounded_rectangle((210, 232, 280, 258), radius=13, fill=(240, 246, 249))
    text(d, (245, 245), "断开", 11, SUB, True, "mm")

    shadow_card(d, (16, 280, 374, 444))
    section(d, 294, "设备信息", "已连接 192.168.1.20:5555", BLUE, "link")
    items = [("型号", "D01"), ("品牌", "XPENG"), ("设备名", "Mona03"),
             ("安卓版本", "11"), ("SDK", "30"), ("序列号", "7b388e10")]
    for i, (k, v) in enumerate(items):
        x = 30 + (i % 2) * 168
        y = 336 + (i // 2) * 34
        d.rounded_rectangle((x, y, x + 158, y + 29), radius=8, fill=(247, 250, 252))
        text(d, (x + 8, y + 4), k, 9, SUB)
        text(d, (x + 8, y + 16), v, 11, TEXT, True)

    shadow_card(d, (16, 458, 374, 556))
    section(d, 470, "截图与录像", "可随时停止 · 无声音", DANGER, "display")
    d.rounded_rectangle((30, 510, 112, 540), radius=13, fill=(231, 249, 245))
    text(d, (71, 525), "截图", 11, MINT, True, "mm")
    d.rounded_rectangle((122, 510, 204, 540), radius=13, fill=(231, 249, 245))
    text(d, (163, 525), "录像", 11, MINT, True, "mm")

    shadow_card(d, (16, 570, 374, 762))
    section(d, 582, "快捷控制", "常用按键与截图", MINT, "bolt")
    controls = [("电源", "⏻"), ("Home", "⌂"), ("返回", "←"),
                ("最近任务", "□"), ("截图", "◎"), ("音量+", "♪")]
    for i, (label, _) in enumerate(controls):
        x = 30 + (i % 3) * 112
        y = 626 + (i // 3) * 64
        d.rounded_rectangle((x, y, x + 102, y + 55), radius=11, fill=(247, 250, 252))
        cx, cy = x + 51, y + 21
        if i == 0:  # power
            d.arc((cx - 9, cy - 9, cx + 9, cy + 9), 40, 320, fill=MINT, width=2)
            d.line((cx, cy - 12, cx, cy - 1), fill=MINT, width=2)
        elif i == 1:  # home
            d.polygon([(cx, cy - 11), (cx - 11, cy - 1), (cx + 11, cy - 1)], fill=MINT)
            d.rectangle((cx - 7, cy - 1, cx + 7, cy + 10), fill=MINT)
        elif i == 2:  # back
            d.line((cx + 9, cy, cx - 9, cy), fill=MINT, width=2)
            d.line((cx - 9, cy, cx - 2, cy - 6), fill=MINT, width=2)
            d.line((cx - 9, cy, cx - 2, cy + 6), fill=MINT, width=2)
        elif i == 3:  # recents
            d.rectangle((cx - 10, cy - 8, cx + 2, cy + 4), outline=MINT, width=2)
            d.rectangle((cx - 2, cy - 2, cx + 10, cy + 10), outline=MINT, width=2)
        elif i == 4:  # camera
            d.rounded_rectangle((cx - 11, cy - 7, cx + 11, cy + 9), radius=3, outline=MINT, width=2)
            d.ellipse((cx - 4, cy - 3, cx + 4, cy + 5), outline=MINT, width=2)
        else:  # volume+
            d.polygon([(cx - 10, cy - 4), (cx - 5, cy - 4), (cx, cy - 9), (cx, cy + 9), (cx - 5, cy + 4), (cx - 10, cy + 4)], fill=MINT)
            d.line((cx + 4, cy, cx + 12, cy), fill=MINT, width=2)
            d.line((cx + 8, cy - 4, cx + 8, cy + 4), fill=MINT, width=2)
        text(d, (x + 51, y + 40), label, 10, TEXT, False, "mm")
    save(img, "01-device.png")


# ---------------- Terminal ----------------
def terminal():
    img, d = base(1, "Shell 终端")
    d.rounded_rectangle((16, 120, 374, 700), radius=18, fill=INK)
    d.rounded_rectangle((16, 120, 374, 168), radius=18, fill=(20, 40, 58))
    d.rectangle((16, 150, 374, 168), fill=(20, 40, 58))
    for i, c in enumerate(((255, 107, 107), (255, 195, 91), (91, 214, 139))):
        d.ellipse((30 + i * 18, 137, 39 + i * 18, 146), fill=c)
    text(d, (195, 143), "shell@android", 11, (160, 180, 195), False, "mm")
    d.rounded_rectangle((286, 133, 360, 155), radius=10, fill=(30, 70, 60))
    d.ellipse((296, 141, 302, 147), fill=(47, 191, 113))
    text(d, (326, 144), "ONLINE", 9, (47, 191, 113), True, "mm")
    lines = [
        ("$ getprop ro.product.model", (168, 243, 216)),
        ("D01", (150, 180, 200)),
        ("$ pm list packages -3", (168, 243, 216)),
        ("package:com.tencent.mm", (150, 180, 200)),
        ("package:com.autonavi.minimap", (150, 180, 200)),
        ("package:com.reathin.adbassist", (150, 180, 200)),
        ("$ wm size", (168, 243, 216)),
        ("Physical size: 1080x2400", (150, 180, 200)),
        ("$ _", (168, 243, 216)),
    ]
    y = 186
    for s, col in lines:
        text(d, (32, y), s, 12, col)
        y += 30
    d.rounded_rectangle((16, 716, 374, 758), radius=14, fill=(255, 255, 255), outline=BORDER)
    text(d, (34, 737), "$", 13, MINT, True)
    text(d, (54, 737), "输入命令…", 12, (175, 186, 196))
    d.ellipse((338, 724, 364, 750), fill=MINT)
    text(d, (351, 736), "↑", 14, (255, 255, 255), True, "mm")
    save(img, "02-terminal.png")


# ---------------- Apps ----------------
def apps():
    img, d = base(2, "应用管理")
    d.rounded_rectangle((16, 116, 374, 148), radius=16, fill=(255, 255, 255), outline=BORDER)
    d.ellipse((30, 126, 38, 134), outline=SUB, width=2)
    d.line((37, 133, 44, 140), fill=SUB, width=2)
    text(d, (54, 131), "搜索包名", 12, SUB)
    d.rounded_rectangle((16, 158, 194, 188), radius=14, fill=(255, 255, 255), outline=BORDER)
    text(d, (105, 173), "用户应用", 12, TEXT, True, "mm")
    d.rounded_rectangle((196, 158, 374, 188), radius=14, fill=(240, 246, 249))
    text(d, (285, 173), "系统应用", 12, SUB, False, "mm")
    apps_list = [
        ("微信", "com.tencent.mm", (76, 191, 96)),
        ("高德地图", "com.autonavi.minimap", (58, 143, 236)),
        ("ADB 助手", "com.reathin.adbhelper", (52, 216, 190)),
        ("设置", "com.android.settings", (130, 145, 160)),
        ("浏览器", "com.android.browser", (255, 169, 90)),
    ]
    y = 202
    for name, pkg, color in apps_list:
        d.rounded_rectangle((16, y, 374, y + 82), radius=16, fill=(255, 255, 255), outline=BORDER)
        d.rounded_rectangle((30, y + 16, 66, y + 52), radius=12, fill=color)
        text(d, (48, y + 26), name[:1], 18, (255, 255, 255), True, "mm")
        text(d, (80, y + 22), name, 13, TEXT, True)
        text(d, (80, y + 44), pkg, 10, SUB)
        d.rounded_rectangle((330, y + 26, 360, y + 52), radius=11, fill=(231, 249, 245))
        text(d, (345, y + 39), "⋯", 14, MINT, False, "mm")
        y += 94
    save(img, "03-apps.png")


# ---------------- Files ----------------
def files():
    img, d = base(3, "文件管理")
    d.rounded_rectangle((16, 116, 374, 150), radius=14, fill=(255, 255, 255), outline=BORDER)
    d.rounded_rectangle((28, 127, 48, 141), radius=5, fill=MINT)
    text(d, (62, 133), "/sdcard/Download", 13, TEXT, False, "lm")
    d.ellipse((340, 126, 358, 144), fill=BLUE)
    text(d, (349, 135), "→", 12, (255, 255, 255), True, "mm")
    chips = ["/sdcard", "/sdcard/Download", "/sdcard/DCIM", "/"]
    x = 16
    for c in chips:
        w = 16 + len(c) * 6
        d.rounded_rectangle((x, 160, x + w, 187), radius=12, fill=(231, 249, 245) if "Download" in c else (240, 246, 249))
        text(d, (x + w // 2, 174), c, 10, MINT if "Download" in c else SUB, False, "mm")
        x += w + 8
    rows = [
        ("IC", "IMG_20261124.jpg", "2.4 MB", (58, 167, 242)),
        ("▶", "demo.mp4", "18.6 MB", (229, 83, 75)),
        ("APK", "adb-helper.apk", "6.1 MB", (52, 216, 190)),
        ("TXT", "notes.txt", "12 KB", (150, 158, 170)),
    ]
    y = 204
    for tag, name, size, color in rows:
        d.rounded_rectangle((16, y, 374, y + 76), radius=16, fill=(255, 255, 255), outline=BORDER)
        d.rounded_rectangle((30, y + 18, 66, y + 54), radius=9, fill=color)
        text(d, (48, y + 28), tag, 11 if len(tag) > 2 else 16, (255, 255, 255), True, "mm")
        text(d, (80, y + 23), name, 13, TEXT, True)
        text(d, (80, y + 45), size + " · 2026-11-24", 10, SUB)
        y += 88
    save(img, "04-files.png")


# ---------------- Settings ----------------
def settings():
    img, d = base(4, "设置")
    shadow_card(d, (16, 116, 374, 280))
    d.rounded_rectangle((30, 132, 92, 194), radius=16, fill=MINT)
    text(d, (61, 163), ">_", 24, (255, 255, 255), True, "mm")
    text(d, (104, 136), "ADB 助手 for iOS", 16, TEXT, True)
    text(d, (104, 160), "通过 Wi-Fi 管理你的 Android 设备", 10, SUB)
    d.line((30, 208, 360, 208), fill=BORDER, width=1)
    rows = [("版本", "1.0.0"), ("授权方式", "RSA 2048 · 需手机确认"), ("快捷命令", "自定义")]
    y = 220
    for k, v in rows:
        text(d, (32, y), k, 11, SUB)
        text(d, (110, y), v, 11, TEXT)
        y += 22

    shadow_card(d, (16, 294, 374, 452))
    section(d, 306, "我的快捷命令", "0 条 · 点垃圾桶删除", MINT, "bolt")
    text(d, (195, 366), "还没有自定义命令", 12, SUB, False, "mm")
    d.rounded_rectangle((30, 398, 186, 430), radius=14, fill=MINT)
    text(d, (108, 414), "+ 添加命令", 11, (255, 255, 255), True, "mm")
    d.rounded_rectangle((196, 398, 360, 430), radius=14, fill=(240, 246, 249))
    text(d, (278, 414), "恢复默认", 11, SUB, True, "mm")

    shadow_card(d, (16, 466, 374, 570))
    section(d, 478, "数据", "仅保存在本机", BLUE, "folder")
    text(d, (34, 522), "清空连接记录（0）", 12, DANGER)
    text(d, (350, 522), "›", 14, SUB, False, "mm")

    shadow_card(d, (16, 584, 374, 756))
    d.rounded_rectangle((30, 598, 60, 628), radius=9, fill=ORANGE)
    text(d, (45, 613), "!", 14, (255, 255, 255), True, "mm")
    text(d, (70, 600), "功能边界", 14, TEXT, True)
    text(d, (30, 638), "未越狱 iOS 无法访问 USB 硬件，不支持 USB ADB、Fastboot 刷机、scrcpy 实时投屏和无线调试配对码配对。本应用支持局域网无线 ADB（TCP 5555）。", 11, SUB)
    save(img, "05-settings.png")


if __name__ == "__main__":
    device()
    terminal()
    apps()
    files()
    settings()
