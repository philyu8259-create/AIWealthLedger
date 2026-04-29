#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = ROOT / "tmp" / "asc_raw"
OUTPUT_ROOT = ROOT / "artifacts" / "app_store_previews"

CN_BOLD_FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
EN_BOLD_FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
EN_REG_FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"


@dataclass(frozen=True)
class Scene:
    slug: str
    raw_name: str
    title_cn: str
    subtitle_cn: str
    title_en: str
    subtitle_en: str
    accent: tuple[int, int, int]


SCENES: tuple[Scene, ...] = (
    Scene(
        slug="01_home",
        raw_name="01_home",
        title_cn="开口记账 拍照识票",
        subtitle_cn="语音拍照都能记 账单一目了然",
        title_en="Just speak or snap\nto log expenses",
        subtitle_en="Skip manual input and make bookkeeping effortless",
        accent=(126, 92, 255),
    ),
    Scene(
        slug="02_ai_overlay",
        raw_name="02_ai_overlay",
        title_cn="AI智能记账",
        subtitle_cn="拍照 语音 手动输入都能识别",
        title_en="AI bookkeeping\nmade easy",
        subtitle_en="Recognize entries from photos, voice, and text",
        accent=(187, 61, 245),
    ),
    Scene(
        slug="03_transactions",
        raw_name="03_transactions",
        title_cn="账单明细 一目了然",
        subtitle_cn="收入支出分组查看 查找回顾更轻松",
        title_en="Review entries with ease",
        subtitle_en="Browse income and expense groups faster every month",
        accent=(90, 77, 235),
    ),
    Scene(
        slug="04_assets_top",
        raw_name="02_assets_top",
        title_cn="为股民量身打造",
        subtitle_cn="自动更新市值和总资产",
        title_en="Built for investors",
        subtitle_en="Track stocks, market value, and total assets automatically",
        accent=(90, 77, 235),
    ),
    Scene(
        slug="05_holdings",
        raw_name="03_holdings",
        title_cn="股票持仓 自动跟踪",
        subtitle_cn="盈亏变化更清楚 资产更新更及时",
        title_en="See your portfolio\nat a glance",
        subtitle_en="Stay on top of gains, losses, and asset changes anytime",
        accent=(65, 188, 120),
    ),
    Scene(
        slug="06_ai_analysis",
        raw_name="04_ai_analysis",
        title_cn="月度财务健康报告",
        subtitle_cn="现金流 异常 风险 预算一次看清",
        title_en="Monthly money\nhealth report",
        subtitle_en="Spot cash flow, anomalies, risks, and budget needs at a glance",
        accent=(247, 146, 52),
    ),
    Scene(
        slug="07_reports",
        raw_name="06_reports",
        title_cn="月度支出分布图",
        subtitle_cn="帮您优化消费结构",
        title_en="See where your money\ngoes every month",
        subtitle_en="Visual reports make spending patterns easy to understand",
        accent=(32, 181, 173),
    ),
    Scene(
        slug="08_settings",
        raw_name="07_settings",
        title_cn="数据安全 云端备份",
        subtitle_cn="换手机 重装app都不怕",
        title_en="Secure backup\nand sync",
        subtitle_en="Your data stays safe even when you switch devices",
        accent=(255, 196, 76),
    ),
)


def font_path(locale: str, bold: bool) -> str:
    if locale == "cn":
        return CN_BOLD_FONT
    return EN_BOLD_FONT if bold else EN_REG_FONT


def load_font(locale: str, size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(font_path(locale, bold=bold), size=size)


def create_background(size: tuple[int, int], accent: tuple[int, int, int]) -> Image.Image:
    width, height = size
    background = Image.new("RGBA", size, (248, 248, 241, 255))
    px = background.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        r = int(248 - 6 * t)
        g = int(248 - 5 * t)
        b = int(241 + 8 * (1 - t))
        for x in range(width):
            px[x, y] = (r, g, b, 255)

    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    blobs = (
        ((int(width * 0.10), int(height * 0.08)), int(width * 0.24), (*accent, 48)),
        ((int(width * 0.83), int(height * 0.12)), int(width * 0.28), (148, 199, 255, 34)),
        ((int(width * 0.46), int(height * 0.54)), int(width * 0.30), (255, 255, 255, 54)),
        ((int(width * 0.18), int(height * 0.72)), int(width * 0.20), (170, 214, 255, 30)),
    )
    for (cx, cy), radius, color in blobs:
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color)

    overlay = overlay.filter(ImageFilter.GaussianBlur(radius=max(width, height) * 0.04))
    background = Image.alpha_composite(background, overlay)

    grid = Image.new("RGBA", size, (0, 0, 0, 0))
    grid_draw = ImageDraw.Draw(grid)
    step = max(int(width * 0.08), 72)
    for x in range(0, width, step):
        grid_draw.line((x, 0, x, height), fill=(255, 255, 255, 18), width=1)
    for y in range(0, height, step):
        grid_draw.line((0, y, width, y), fill=(255, 255, 255, 14), width=1)
    grid = grid.filter(ImageFilter.GaussianBlur(radius=1.2))
    return Image.alpha_composite(background, grid)


def fit_text_lines(
    draw: ImageDraw.ImageDraw,
    text: str,
    locale: str,
    max_width: int,
    start_size: int,
    min_size: int,
    bold: bool,
    line_spacing: float = 1.10,
) -> tuple[ImageFont.FreeTypeFont, list[str], int]:
    candidate_lines = text.split("\n")
    for size in range(start_size, min_size - 1, -2):
        font = load_font(locale, size=size, bold=bold)
        too_wide = False
        for line in candidate_lines:
            bbox = draw.textbbox((0, 0), line, font=font)
            if (bbox[2] - bbox[0]) > max_width:
                too_wide = True
                break
        if not too_wide:
            line_height = int(size * line_spacing)
            return font, candidate_lines, line_height
    font = load_font(locale, size=min_size, bold=bold)
    return font, candidate_lines, int(min_size * line_spacing)


def round_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def add_shadow(base: Image.Image, mask: Image.Image, box: tuple[int, int], blur: int, color: tuple[int, int, int, int]) -> None:
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    x, y = box
    shadow_layer = Image.new("RGBA", mask.size, color)
    shadow.paste(shadow_layer, (x, y), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=blur))
    base.alpha_composite(shadow)


def compose_device(
    canvas: Image.Image,
    raw: Image.Image,
    scene: Scene,
    device_kind: str,
    locale: str,
    top_y: int,
) -> None:
    width, height = canvas.size
    crop = raw

    if device_kind == "iphone":
        outer_w = int(width * 0.94)
        max_h = int(height * 0.82)
        bezel = max(int(width * 0.013), 10)
        radius = int(outer_w * 0.115)
        inset_radius = max(radius - bezel * 2, 28)
    else:
        outer_w = int(width * 0.96)
        max_h = int(height * 0.79)
        bezel = max(int(width * 0.008), 8)
        radius = int(outer_w * 0.060)
        inset_radius = max(radius - bezel * 2, 24)

    scale = min(outer_w / crop.size[0], max_h / crop.size[1])
    screen_size = (int(crop.size[0] * scale), int(crop.size[1] * scale))
    crop = crop.resize(screen_size, Image.Resampling.LANCZOS)
    outer_size = (screen_size[0] + bezel * 2, screen_size[1] + bezel * 2)

    frame = Image.new("RGBA", outer_size, (0, 0, 0, 0))
    outer_mask = round_mask(outer_size, radius)
    frame_bg = Image.new("RGBA", outer_size, (16, 18, 24, 255))
    frame.paste(frame_bg, (0, 0), outer_mask)

    screen = Image.new("RGBA", outer_size, (0, 0, 0, 0))
    screen_mask = round_mask(screen_size, inset_radius)
    screen.paste(crop, (bezel, bezel), screen_mask)
    frame.alpha_composite(screen)

    gloss = Image.new("RGBA", outer_size, (0, 0, 0, 0))
    gloss_draw = ImageDraw.Draw(gloss)
    gloss_draw.rounded_rectangle(
        (bezel // 2, bezel // 2, outer_size[0] - bezel // 2, outer_size[1] - bezel // 2),
        radius=radius,
        outline=(255, 255, 255, 42),
        width=max(1, bezel // 3),
    )
    gloss = gloss.filter(ImageFilter.GaussianBlur(radius=0.6))
    frame.alpha_composite(gloss)

    x = (width - outer_size[0]) // 2
    y = top_y
    add_shadow(
        canvas,
        outer_mask,
        (x, y + int(height * 0.004)),
        blur=max(24, width // 34),
        color=(44, 41, 78, 64),
    )
    canvas.alpha_composite(frame, (x, y))


def draw_text_block(canvas: Image.Image, scene: Scene, locale: str) -> int:
    draw = ImageDraw.Draw(canvas)
    width, height = canvas.size
    title = scene.title_cn if locale == "cn" else scene.title_en
    subtitle = scene.subtitle_cn if locale == "cn" else scene.subtitle_en

    title_max_w = int(width * (0.86 if locale == "cn" else 0.82))
    title_font, title_lines, title_line_h = fit_text_lines(
        draw,
        title,
        locale,
        max_width=title_max_w,
        start_size=int(width * (0.060 if locale == "cn" else 0.058)),
        min_size=int(width * 0.034),
        bold=True,
        line_spacing=1.02,
    )
    y = int(height * 0.038)
    for line in title_lines:
        bbox = draw.textbbox((0, 0), line, font=title_font)
        line_w = bbox[2] - bbox[0]
        draw.text(
            ((width - line_w) / 2, y),
            line,
            font=title_font,
            fill=(34, 39, 55, 255),
            embedded_color=False,
        )
        y += title_line_h

    if subtitle:
        subtitle_font, subtitle_lines, subtitle_line_h = fit_text_lines(
            draw,
            subtitle,
            locale,
            max_width=int(width * (0.80 if locale == "cn" else 0.76)),
            start_size=int(width * (0.026 if locale == "cn" else 0.024)),
            min_size=int(width * 0.018),
            bold=False,
            line_spacing=1.10,
        )
        y += int(height * 0.008 if locale == "cn" else height * 0.006)
        for line in subtitle_lines:
            bbox = draw.textbbox((0, 0), line, font=subtitle_font)
            line_w = bbox[2] - bbox[0]
            draw.text(
                ((width - line_w) / 2, y),
                line,
                font=subtitle_font,
                fill=(110, 117, 136, 255),
            )
            y += subtitle_line_h

    y += int(height * 0.010)
    line_w = int(width * 0.16)
    line_h = max(4, width // 180)
    accent = Image.new("RGBA", (line_w, line_h), (*scene.accent, 200))
    accent = accent.filter(ImageFilter.GaussianBlur(radius=line_h // 2))
    accent_y = y
    canvas.alpha_composite(accent, ((width - line_w) // 2, accent_y))
    return accent_y + line_h


def build_one(
    raw_path: Path,
    out_path: Path,
    scene: Scene,
    locale: str,
    device_kind: str,
) -> None:
    raw = Image.open(raw_path).convert("RGBA")
    canvas = create_background(raw.size, scene.accent)
    text_bottom_y = draw_text_block(canvas, scene, locale=locale)
    device_top_y = text_bottom_y + int(raw.size[1] * 0.028)
    compose_device(
        canvas,
        raw,
        scene,
        device_kind=device_kind,
        locale=locale,
        top_y=device_top_y,
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path, quality=95)


def generate_contact_sheet(images: Iterable[Path], out_path: Path, columns: int = 4) -> None:
    paths = list(images)
    if not paths:
        return
    thumbs = [Image.open(path).convert("RGB") for path in paths]
    thumb_w = 240
    thumb_h = int(thumb_w * thumbs[0].size[1] / thumbs[0].size[0])
    gap = 28
    rows = (len(thumbs) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (columns * thumb_w + (columns + 1) * gap, rows * thumb_h + (rows + 1) * gap),
        (246, 246, 242),
    )
    for idx, image in enumerate(thumbs):
        resized = image.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        x = gap + (idx % columns) * (thumb_w + gap)
        y = gap + (idx // columns) * (thumb_h + gap)
        sheet.paste(resized, (x, y))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, quality=92)


def main() -> None:
    variants = (
        ("phone_cn", "cn", "iphone"),
        ("phone_en", "intl", "iphone"),
        ("ipad_cn", "cn", "ipad"),
        ("ipad_en", "intl", "ipad"),
    )
    for folder, locale, device_kind in variants:
        final_paths: list[Path] = []
        for scene in SCENES:
            raw_path = RAW_ROOT / folder / f"{scene.raw_name}.png"
            out_path = OUTPUT_ROOT / folder / f"{scene.slug}.png"
            build_one(raw_path, out_path, scene, locale=locale, device_kind=device_kind)
            final_paths.append(out_path)
        generate_contact_sheet(final_paths, OUTPUT_ROOT / folder / "_contact_sheet.jpg")


if __name__ == "__main__":
    main()
