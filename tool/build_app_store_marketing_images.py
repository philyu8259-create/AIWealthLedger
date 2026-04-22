#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = ROOT / "tmp" / "appstore_screenshots" / "sources"
OUT_ROOT = ROOT / "tmp" / "appstore_screenshots" / "composites"

COPY = {
    "cn": [
        ("开口就能记 拍照也能记", "不想手动输入时 更能感受到它的方便", "05_ai_sheet.png"),
        ("专为股民打造的记账工具", "股票 市值 总资产自动同步更新", "02_asset.png"),
        ("持仓盈亏一眼看懂", "不用反复切 app 资产变化随时掌握", "02_asset.png"),
        ("AI帮你看懂每一笔开销", "自动分析消费结构 给出预算建议", "04_analysis.png"),
        ("股票基金现金统一管理", "不同资产放在一起 看得更全更清楚", "01_home.png"),
        ("每月花在哪 一张图看明白", "支出分布 趋势变化 都能快速掌握", "03_reports.png"),
        ("数据安全 云端同步备份", "换手机 重装 app 账单也不会丢", "08_settings.png"),
        ("AI智能记账 真的更省事", "拍照 语音 输入内容都能自动识别", "05_ai_sheet.png"),
    ],
    "en": [
        ("Just speak or snap to log expenses", "Skip manual input and make bookkeeping effortless", "05_ai_sheet.png"),
        ("Built for investors", "Track stocks, market value, and total assets automatically", "02_asset.png"),
        ("See your portfolio at a glance", "Stay on top of gains, losses, and asset changes anytime", "02_asset.png"),
        ("Let AI analyze your spending", "Understand expenses faster and get smarter budget suggestions", "04_analysis.png"),
        ("Manage all assets in one place", "Stocks, funds, cash, and bank accounts, all clearly organized", "01_home.png"),
        ("See where your money goes every month", "Visual reports make spending patterns easy to understand", "03_reports.png"),
        ("Secure backup and sync", "Your data stays safe even when you switch devices", "08_settings.png"),
        ("AI bookkeeping made easy", "Automatically recognize entries from photos, voice, and text", "05_ai_sheet.png"),
    ],
}

FONT_CN = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_CN_BOLD = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_CN_SUB_BOLD = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_EN = "/System/Library/Fonts/SFNS.ttf"
FONT_EN_BOLD = "/System/Library/Fonts/SFNSRounded.ttf"
FONT_EN_SUB_BOLD = "/System/Library/Fonts/SFNSRounded.ttf"
FONT_FALLBACK = "/System/Library/Fonts/Helvetica.ttc"

TITLE_COLOR = (45, 78, 71, 255)
SUBTITLE_COLOR = (95, 110, 108, 255)
BG_COLOR = (244, 247, 241, 255)
FRAME_COLOR = (25, 25, 27, 255)


def load_font(path: str, size: int):
    for p in [path, FONT_FALLBACK]:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


def text_width(font, text: str) -> int:
    box = font.getbbox(text)
    return box[2] - box[0]


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def wrap_text(text: str, font, max_width: int, lang: str):
    if lang == "cn":
        units = list(text.replace("\n", ""))
        sep = ""
    else:
        units = text.split()
        sep = " "

    lines = []
    current = []
    for unit in units:
        candidate = sep.join(current + [unit]) if current else unit
        if text_width(font, candidate) <= max_width:
            current.append(unit)
        else:
            if current:
                lines.append(sep.join(current))
            current = [unit]
    if current:
        lines.append(sep.join(current))
    return lines


def add_soft_background(canvas: Image.Image, idx: int):
    w, h = canvas.size
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    palettes = [
        ((193, 236, 220, 110), (208, 232, 255, 90), (255, 229, 186, 70)),
        ((200, 236, 218, 95), (196, 228, 255, 100), (255, 240, 205, 60)),
        ((204, 238, 224, 100), (212, 230, 255, 90), (255, 235, 198, 55)),
    ]
    a, b, c = palettes[idx % len(palettes)]
    draw.ellipse((int(-0.12 * w), int(0.14 * h), int(0.30 * w), int(0.60 * h)), fill=a)
    draw.ellipse((int(0.72 * w), int(0.06 * h), int(1.06 * w), int(0.34 * h)), fill=b)
    draw.ellipse((int(0.18 * w), int(0.00 * h), int(0.62 * w), int(0.18 * h)), fill=c)
    draw.ellipse((int(0.68 * w), int(0.68 * h), int(1.02 * w), int(0.96 * h)), fill=(215, 236, 228, 70))
    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=int(min(w, h) * 0.035)))
    canvas.alpha_composite(overlay)


def fit_image(src: Image.Image, target_w: int, target_h: int) -> Image.Image:
    ratio = min(target_w / src.width, target_h / src.height)
    new_size = (max(1, int(src.width * ratio)), max(1, int(src.height * ratio)))
    return src.resize(new_size, Image.Resampling.LANCZOS)


def paste_center(base: Image.Image, fg: Image.Image, x: int, y: int, w: int, h: int):
    resized = fit_image(fg, w, h)
    px = x + (w - resized.width) // 2
    py = y + (h - resized.height) // 2
    base.alpha_composite(resized, (px, py))


def draw_phone_mockup(base: Image.Image, screenshot: Image.Image, box):
    x, y, w, h = box
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    shadow_card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow_card).rounded_rectangle((0, 0, w, h), radius=int(w * 0.09), fill=(0, 0, 0, 90))
    shadow.alpha_composite(shadow_card.filter(ImageFilter.GaussianBlur(radius=26)), (x, y + int(h * 0.02)))
    base.alpha_composite(shadow)

    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame, "RGBA")
    radius = int(w * 0.09)
    d.rounded_rectangle((0, 0, w, h), radius=radius, fill=FRAME_COLOR)
    d.rounded_rectangle((int(w * 0.010), int(h * 0.010), int(w * 0.990), int(h * 0.990)), radius=int(radius * 0.95), outline=(70, 70, 72, 255), width=max(2, int(w * 0.005)))

    screen_margin_x = int(w * 0.022)
    screen_margin_top = int(h * 0.020)
    screen_margin_bottom = int(h * 0.010)
    screen_w = w - screen_margin_x * 2
    screen_h = h - screen_margin_top - screen_margin_bottom
    screen = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS).convert("RGBA")
    mask = rounded_mask((screen_w, screen_h), int(w * 0.072))
    frame.paste(screen, (screen_margin_x, screen_margin_top), mask)

    base.alpha_composite(frame, (x, y))


def draw_ipad_mockup(base: Image.Image, screenshot: Image.Image, box):
    x, y, w, h = box
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    shadow_card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow_card).rounded_rectangle((0, 0, w, h), radius=int(w * 0.045), fill=(0, 0, 0, 80))
    shadow.alpha_composite(shadow_card.filter(ImageFilter.GaussianBlur(radius=28)), (x, y + int(h * 0.02)))
    base.alpha_composite(shadow)

    frame = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame, "RGBA")
    radius = int(w * 0.045)
    d.rounded_rectangle((0, 0, w, h), radius=radius, fill=FRAME_COLOR)

    bezel = int(w * 0.028)
    screen_w = w - bezel * 2
    screen_h = h - bezel * 2
    screen = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS).convert("RGBA")
    mask = rounded_mask((screen_w, screen_h), int(radius * 0.72))
    frame.paste(screen, (bezel, bezel), mask)

    cam_r = max(4, int(w * 0.006))
    cam_x = w // 2
    cam_y = bezel // 2 + 4
    d.ellipse((cam_x - cam_r, cam_y - cam_r, cam_x + cam_r, cam_y + cam_r), fill=(55, 55, 58, 255))
    base.alpha_composite(frame, (x, y))


def build_one(source_path: Path, out_path: Path, title: str, subtitle: str, lang: str, idx: int):
    src = Image.open(source_path).convert("RGBA")
    w, h = src.size
    canvas = Image.new("RGBA", (w, h), BG_COLOR)
    add_soft_background(canvas, idx)
    draw = ImageDraw.Draw(canvas, "RGBA")

    is_ipad = w > 1800
    title_font = load_font(FONT_CN_BOLD if lang == "cn" else FONT_EN_BOLD, 104 if is_ipad else 82)
    subtitle_font = load_font(FONT_CN_SUB_BOLD if lang == "cn" else FONT_EN_SUB_BOLD, 48 if is_ipad else 38)

    title_max = int(w * 0.86)
    sub_max = int(w * 0.78)
    title_lines = wrap_text(title, title_font, title_max, lang)
    subtitle_lines = wrap_text(subtitle, subtitle_font, sub_max, lang)

    current_y = int(h * (0.055 if is_ipad else 0.035))
    for line in title_lines:
        line_w = text_width(title_font, line)
        draw.text(((w - line_w) / 2, current_y), line, font=title_font, fill=TITLE_COLOR)
        current_y += int(title_font.size * 1.04)

    current_y += int(h * 0.012)
    for line in subtitle_lines:
        line_w = text_width(subtitle_font, line)
        draw.text(((w - line_w) / 2, current_y), line, font=subtitle_font, fill=SUBTITLE_COLOR)
        current_y += int(subtitle_font.size * 1.18)

    if is_ipad:
        device_w = int(w * 0.75)
        device_h = int(h * 0.68)
        device_x = (w - device_w) // 2
        device_y = h - device_h - int(h * 0.085)
        draw_ipad_mockup(canvas, src, (device_x, device_y, device_w, device_h))
    else:
        device_w = int(w * 0.79)
        device_h = int(h * 0.80)
        device_x = (w - device_w) // 2
        device_y = h - device_h - int(h * 0.07)
        draw_phone_mockup(canvas, src, (device_x, device_y, device_w, device_h))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path, quality=100)


def main():
    tasks = [
        ("iphone69_cn", "cn"),
        ("iphone69_en", "en"),
        ("ipad13_cn", "cn"),
        ("ipad13_en", "en"),
    ]

    for folder, lang in tasks:
        for idx, (title, subtitle, source_name) in enumerate(COPY[lang], start=1):
            source_path = SRC_ROOT / folder / source_name
            out_path = OUT_ROOT / folder / f"{idx:02d}.png"
            build_one(source_path, out_path, title, subtitle, lang, idx - 1)
            print(f"built {out_path}")


if __name__ == "__main__":
    main()
