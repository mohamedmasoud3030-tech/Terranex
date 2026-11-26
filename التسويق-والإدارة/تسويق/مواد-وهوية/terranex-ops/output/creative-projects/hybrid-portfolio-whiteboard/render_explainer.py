#!/usr/bin/env python3
"""Render the TerraNex hybrid cattle/Barki whiteboard explainer.

Local inputs: approved company footage, brand kit, and Arena-generated narration.
Output: the tracked 16:9 delivery folder (not terranex-ops/output/).
"""
from __future__ import annotations

import argparse
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps
from moviepy import (
    AudioFileClip,
    CompositeAudioClip,
    CompositeVideoClip,
    ImageClip,
    VideoFileClip,
    concatenate_videoclips,
    afx,
    vfx,
)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[6]
OPS = ROOT / "التسويق-والإدارة" / "تسويق" / "مواد-وهوية" / "terranex-ops"
ENGINE = OPS / "engine"
sys.path.insert(0, str(ENGINE))
import brand  # noqa: E402

W, H, FPS = 1920, 1080, 25
BG = brand.hex2rgb(brand.C["bg_cream"])
INK = brand.hex2rgb(brand.C["ink"])
GREEN = brand.hex2rgb(brand.C["green"])
GREEN_DEEP = brand.hex2rgb(brand.C["green_deep"])
GOLD = brand.hex2rgb(brand.C["gold"])
GOLD_MID = brand.hex2rgb(brand.C["gold_mid"])
GOLD_HI = brand.hex2rgb(brand.C["gold_hi"])
MUTED = brand.hex2rgb(brand.C["muted"])
WHITE = brand.hex2rgb(brand.C["white"])
MEDIA = (1087, 302, 736, 456)
SCENE_DURATIONS: list[float] = []
VIDEO_CACHE: dict[str, VideoFileClip] = {}
AUDIO_CACHE: list[AudioFileClip] = []

SOURCE_COW = ROOT / "التسويق-والإدارة" / "تسويق" / "فيديوهات-جاهزة-للنشر" / "01-بومو-الشركة-الرئيسي.mp4"
RAW = ROOT / "التسويق-والإدارة" / "تسويق" / "مواد-خام" / "أرشيف" / "2026-11" / "فيديوهات-حيوانات-ومزارع"
SOURCE_SHEEP_1 = RAW / "gh-a18.mp4"
SOURCE_SHEEP_2 = RAW / "gh-a21.mp4"
VOICE_DIR = HERE / "voice"
VOICE_FILES = [VOICE_DIR / f"short-scene-{i:02d}.mp3" for i in range(1, 6)]
STORYBOARD = HERE / "_storyboard"
BUILD_DIR = HERE / "_build"
OUTPUT = ROOT / "التسويق-والإدارة" / "تسويق" / "فيديوهات-المنتجة" / "2026-11" / "TerraNex_Whiteboard_Explainer.mp4"


def rgba(rgb: tuple[int, int, int], alpha: int = 255) -> tuple[int, int, int, int]:
    return rgb[0], rgb[1], rgb[2], alpha


def draw_text(
    image: Image.Image,
    xy: tuple[int, int],
    text: str,
    size: int,
    color: tuple[int, int, int] = INK,
    weight: str = "bold",
    anchor: str = "mm",
    direction: str = "rtl",
) -> None:
    d = ImageDraw.Draw(image)
    brand.text(d, xy, text, brand.font(weight, size), color, anchor=anchor, direction=direction)


def new_layer() -> Image.Image:
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def draw_header(image: Image.Image, scene_no: int, title: str, has_cards: bool = True) -> None:
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((90, 55, 1830, 71), radius=8, fill=rgba(GOLD_HI, 255))
    filled = 90 + int(1740 * scene_no / 5)
    d.rounded_rectangle((90, 55, filled, 71), radius=8, fill=rgba(GREEN, 255))
    for i in range(1, 6):
        x = 90 + int(1740 * i / 5)
        d.ellipse((x - 7, 50, x + 7, 76), fill=rgba(GOLD_MID if i <= scene_no else GOLD_HI, 255))
    draw_text(image, (1775, 122), f"{scene_no:02d} / 05", 28, MUTED, "bold", "mm", "ltr")
    draw_text(image, (960, 171), title, 74, INK, "black")
    d.line((135, 244, 1785, 244), fill=rgba(GOLD_MID, 255), width=3)

    if has_cards:
        d.rounded_rectangle((90, 292, 1010, 856), radius=30, fill=rgba(WHITE, 255), outline=rgba(GOLD_HI, 255), width=3)
        d.rounded_rectangle((1075, 292, 1840, 768), radius=30, fill=rgba(WHITE, 255), outline=rgba(GREEN, 220), width=3)
        draw_text(image, (1457, 805), "لقطات من مواد المزرعة", 30, MUTED, "medium")
    brand.watermark(image, pos="bl", theme="light", alpha=205, with_emblem=True)


def draw_cow(d: ImageDraw.ImageDraw, cx: int, cy: int, s: float = 1.0) -> None:
    """Simple hand-drawn cow icon using brand colors (not generated imagery)."""
    lw = max(3, int(7 * s))
    def p(x, y):
        return int(cx + x * s), int(cy + y * s)
    def box(x0, y0, x1, y1):
        return int(cx + x0 * s), int(cy + y0 * s), int(cx + x1 * s), int(cy + y1 * s)
    # Body and shoulder.
    d.ellipse(box(-185, -58, 105, 105), fill=rgba(WHITE), outline=rgba(GREEN), width=lw)
    d.ellipse(box(-60, -44, 26, 31), fill=rgba(GOLD_HI), outline=rgba(GOLD_MID), width=max(2, lw // 2))
    d.ellipse(box(37, 6, 95, 69), fill=rgba(GOLD_HI), outline=rgba(GOLD_MID), width=max(2, lw // 2))
    # Head, muzzle, ears, and horns.
    d.ellipse(box(71, -39, 197, 74), fill=rgba(WHITE), outline=rgba(GREEN), width=lw)
    d.ellipse(box(159, 10, 233, 60), fill=rgba(GOLD_HI), outline=rgba(GREEN), width=max(3, lw - 1))
    d.line([p(103, -29), p(82, -66), p(126, -43)], fill=rgba(GREEN), width=lw, joint="curve")
    d.line([p(161, -29), p(181, -63), p(181, -19)], fill=rgba(GREEN), width=lw, joint="curve")
    d.line([p(78, -12), p(39, -37), p(89, -28)], fill=rgba(GREEN), width=lw)
    d.ellipse(box(142, -9, 151, 1), fill=rgba(INK))
    # Legs and tail.
    for x in (-132, -54, 31, 74):
        d.line([p(x, 82), p(x - 3, 152)], fill=rgba(GREEN), width=lw)
        d.line([p(x - 13, 154), p(x + 9, 154)], fill=rgba(GOLD_MID), width=max(3, lw - 1))
    d.line([p(-176, -20), p(-218, -58), p(-221, -95)], fill=rgba(GREEN), width=lw)
    d.ellipse(box(-227, -103, -215, -91), fill=rgba(GOLD_MID))


def draw_sheep(d: ImageDraw.ImageDraw, cx: int, cy: int, s: float = 1.0) -> None:
    """Simple hand-drawn sheep icon using brand colors (not generated imagery)."""
    lw = max(3, int(7 * s))
    def p(x, y):
        return int(cx + x * s), int(cy + y * s)
    def box(x0, y0, x1, y1):
        return int(cx + x0 * s), int(cy + y0 * s), int(cx + x1 * s), int(cy + y1 * s)
    # Woolly outline and body.
    circles = [(-142, -5, 62), (-92, -48, 68), (-21, -56, 68), (51, -40, 66), (105, 3, 60), (48, 45, 67), (-28, 53, 67), (-105, 43, 61)]
    for dx, dy, r in circles:
        d.ellipse(box(dx - r, dy - r, dx + r, dy + r), fill=rgba(WHITE), outline=rgba(GREEN), width=lw)
    # Face and ears.
    d.ellipse(box(98, -56, 197, 67), fill=rgba(GOLD_HI), outline=rgba(GREEN), width=lw)
    d.ellipse(box(165, -24, 222, 18), fill=rgba(WHITE), outline=rgba(GREEN), width=max(3, lw - 1))
    d.line([p(114, -37), p(143, -72), p(151, -35)], fill=rgba(GREEN), width=lw)
    d.line([p(144, -42), p(171, -65), p(173, -33)], fill=rgba(GREEN), width=lw)
    d.ellipse(box(150, -4, 159, 5), fill=rgba(INK))
    # Legs.
    for x in (-96, -23, 46, 95):
        d.line([p(x, 73), p(x - 3, 145)], fill=rgba(GREEN), width=lw)
        d.line([p(x - 12, 148), p(x + 10, 148)], fill=rgba(GOLD_MID), width=max(3, lw - 1))


def draw_check_row(layer: Image.Image, y: int, title: str, detail: str | None = None) -> None:
    d = ImageDraw.Draw(layer)
    d.ellipse((150, y - 34, 220, y + 36), fill=rgba(WHITE), outline=rgba(GOLD_MID), width=4)
    d.line((169, y + 1, 184, y + 15, 205, y - 12), fill=rgba(GREEN), width=6, joint="curve")
    draw_text(layer, (920, y - (13 if detail else 0)), title, 42, INK, "bold", "rm")
    if detail:
        draw_text(layer, (920, y + 26), detail, 29, MUTED, "medium", "rm")


def rounded_photo(image: Image.Image, size: tuple[int, int], radius: int = 22) -> Image.Image:
    photo = ImageOps.fit(image.convert("RGB"), size, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5)).convert("RGBA")
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    photo.putalpha(mask)
    return photo


def get_source(path: Path) -> VideoFileClip:
    key = str(path)
    if key not in VIDEO_CACHE:
        clip = VideoFileClip(key, audio=False)
        VIDEO_CACHE[key] = clip
    return VIDEO_CACHE[key]


def media_still(path: Path, t: float) -> Image.Image:
    src = get_source(path)
    return Image.fromarray(src.get_frame(min(max(t, 0.0), src.duration - 0.05))).convert("RGB")


def draw_intro_photos(image: Image.Image, cow_frame: Image.Image, sheep_frame: Image.Image) -> None:
    x, y, w, h = MEDIA
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((x - 6, y - 6, x + w + 6, y + h + 88), radius=28, fill=rgba(WHITE), outline=rgba(GREEN), width=4)
    photo_w = (w - 28) // 2
    photo_h = h - 78
    p1 = rounded_photo(cow_frame, (photo_w, photo_h), 18)
    p2 = rounded_photo(sheep_frame, (photo_w, photo_h), 18)
    image.alpha_composite(p1, (x + 8, y + 8))
    image.alpha_composite(p2, (x + 20 + photo_w, y + 8))
    d = ImageDraw.Draw(image)
    d.line((x + w // 2, y + 17, x + w // 2, y + h - 6), fill=rgba(GOLD_MID), width=4)
    d.rounded_rectangle((x + 8, y + h - 62, x + 8 + photo_w, y + h - 4), radius=14, fill=rgba(GREEN_DEEP, 245))
    d.rounded_rectangle((x + 20 + photo_w, y + h - 62, x + w - 8, y + h - 4), radius=14, fill=rgba(GREEN_DEEP, 245))
    draw_text(image, (x + 8 + photo_w // 2, y + h - 33), "العجل", 34, WHITE, "bold")
    draw_text(image, (x + 20 + photo_w + photo_w // 2, y + h - 33), "البرقي", 34, WHITE, "bold")
    draw_text(image, (x + w // 2, y + h + 52), "لقطتان حقيقيتان من مواد المزرعة", 28, MUTED, "medium")


def round_mask_clip(size: tuple[int, int], duration: float) -> ImageClip:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=22, fill=255)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    return ImageClip(arr, is_mask=True).with_duration(duration)


def fit_video(clip: VideoFileClip, size: tuple[int, int]):
    w, h = size
    scale = max(w / clip.w, h / clip.h)
    resized = clip.resized(scale)
    x1 = max(0, int((resized.w - w) / 2))
    y1 = max(0, int((resized.h - h) / 2))
    return resized.cropped(x1=x1, y1=y1, x2=x1 + w, y2=y1 + h)


def build_media(path: Path, start: float, end: float, duration: float):
    source = get_source(path)
    end = min(end, source.duration - 0.05)
    start = min(start, end - 0.2)
    segment = fit_video(source.subclipped(start, end).without_audio(), (MEDIA[2] - 16, MEDIA[3] - 16))
    moving_duration = segment.duration
    if moving_duration >= duration - 0.05:
        panel = segment.with_duration(duration)
    else:
        last = ImageClip(segment.get_frame(max(0, moving_duration - 0.04))).with_duration(duration - moving_duration + 0.35)
        last = last.with_start(max(0, moving_duration - 0.35)).with_effects([vfx.CrossFadeIn(0.35)])
        panel = CompositeVideoClip([segment, last], size=(MEDIA[2] - 16, MEDIA[3] - 16), bg_color=WHITE).with_duration(duration)
    panel = panel.with_mask(round_mask_clip((MEDIA[2] - 16, MEDIA[3] - 16), duration))
    return panel.with_position((MEDIA[0] + 8, MEDIA[1] + 8))


def draw_panel_frame(layer: Image.Image) -> None:
    d = ImageDraw.Draw(layer)
    x, y, w, h = MEDIA
    d.rounded_rectangle((x, y, x + w, y + h), radius=28, outline=rgba(GREEN), width=5)
    d.line((x + 26, y + h + 18, x + w - 26, y + h + 18), fill=rgba(GOLD_HI), width=3)


def add_reveal(clips: list, layer: Image.Image, start: float, duration: float) -> None:
    if start >= duration:
        return
    length = duration - start
    clip = ImageClip(np.asarray(layer), transparent=True).with_start(start).with_duration(length)
    if length > 0.35:
        clip = clip.with_effects([vfx.FadeIn(0.28)])
    clips.append(clip)


def scene_base(scene_no: int, title: str, has_cards: bool = True) -> Image.Image:
    image = Image.new("RGBA", (W, H), rgba(BG))
    draw_header(image, scene_no, title, has_cards=has_cards)
    return image


def make_scene_1(duration: float) -> CompositeVideoClip:
    base = scene_base(1, "محفظة بأدوار مختلفة")
    d = ImageDraw.Draw(base)
    # Two empty asset cards, then their hand-drawn icons are revealed in sequence.
    d.rounded_rectangle((125, 336, 525, 678), radius=24, fill=rgba(WHITE), outline=rgba(GOLD_HI), width=3)
    d.rounded_rectangle((572, 336, 972, 678), radius=24, fill=rgba(WHITE), outline=rgba(GOLD_HI), width=3)
    cow_frame = media_still(SOURCE_COW, 11.5)
    sheep_frame = media_still(SOURCE_COW, 10.2)
    sheep_frame = sheep_frame.crop((0, 0, sheep_frame.width, int(sheep_frame.height * 0.78)))
    draw_intro_photos(base, cow_frame, sheep_frame)
    draw_text(base, (548, 831), "دورة مختلفة لكل أصل", 28, MUTED, "medium")

    reveal1 = new_layer()
    draw_cow(ImageDraw.Draw(reveal1), 325, 480, 0.54)
    draw_text(reveal1, (325, 619), "العجل", 39, INK, "bold")

    reveal2 = new_layer()
    draw_sheep(ImageDraw.Draw(reveal2), 775, 480, 0.52)
    draw_text(reveal2, (775, 619), "البرقي", 39, INK, "bold")

    reveal3 = new_layer()
    d3 = ImageDraw.Draw(reveal3)
    d3.line((325, 699, 325, 730, 775, 730, 775, 699), fill=rgba(GOLD_MID), width=5, joint="curve")
    d3.rounded_rectangle((385, 747, 715, 799), radius=24, fill=rgba(GREEN_DEEP), outline=rgba(GOLD), width=3)
    draw_text(reveal3, (550, 773), "محفظة واحدة", 31, WHITE, "bold")

    clips = [ImageClip(np.asarray(base.convert("RGB"))).with_duration(duration)]
    add_reveal(clips, reveal1, 0.6, duration)
    add_reveal(clips, reveal2, 6.7, duration)
    add_reveal(clips, reveal3, 14.0, duration)
    return CompositeVideoClip(clips, size=(W, H), bg_color=BG).with_duration(duration)


def make_scene_2(duration: float) -> CompositeVideoClip:
    base = scene_base(2, "العجل: دورة متابعة مستقلة")
    d = ImageDraw.Draw(base)
    draw_cow(d, 545, 405, 0.49)
    draw_text(base, (540, 535), "رعاية · تغذية · متابعة", 34, MUTED, "medium")
    note = new_layer()
    draw_text(note, (550, 834), "لا نفترض أرقامًا قبل المراجعة", 25, MUTED, "medium")

    rows = [new_layer() for _ in range(3)]
    draw_check_row(rows[0], 610, "رعاية كل دفعة")
    draw_check_row(rows[1], 690, "تغذية وفق الخطة")
    draw_check_row(rows[2], 770, "وزن مسجّل بتاريخ المتابعة")
    clips = [ImageClip(np.asarray(base.convert("RGB"))).with_duration(duration)]
    clips.append(build_media(SOURCE_COW, 19.0, 21.02, duration))
    draw_panel_frame_layer = new_layer()
    draw_panel_frame(draw_panel_frame_layer)
    clips.append(ImageClip(np.asarray(draw_panel_frame_layer), transparent=True).with_duration(duration))
    for row, start in zip(rows, (1.0, 7.4, 14.4)):
        add_reveal(clips, row, start, duration)
    add_reveal(clips, note, 15.5, duration)
    return CompositeVideoClip(clips, size=(W, H), bg_color=BG).with_duration(duration)


def make_scene_3(duration: float) -> CompositeVideoClip:
    base = scene_base(3, "البرقي: مكوّن مختلف")
    d = ImageDraw.Draw(base)
    draw_sheep(d, 545, 405, 0.49)
    draw_text(base, (540, 535), "دورة رعاية ومتابعة خاصة", 34, MUTED, "medium")
    note = new_layer()
    draw_text(note, (550, 834), "اختلاف الأصل يغيّر طريقة المراجعة", 25, MUTED, "medium")

    rows = [new_layer() for _ in range(3)]
    draw_check_row(rows[0], 610, "متابعة الحالة")
    draw_check_row(rows[1], 690, "رعاية وتغذية")
    draw_check_row(rows[2], 770, "بيانات مستقلة لكل مجموعة")
    clips = [ImageClip(np.asarray(base.convert("RGB"))).with_duration(duration)]
    clips.append(build_media(SOURCE_SHEEP_1, 2.5, 9.8, duration))
    frame = new_layer(); draw_panel_frame(frame)
    clips.append(ImageClip(np.asarray(frame), transparent=True).with_duration(duration))
    for row, start in zip(rows, (1.0, 7.0, 13.2)):
        add_reveal(clips, row, start, duration)
    add_reveal(clips, note, 18.5, duration)
    return CompositeVideoClip(clips, size=(W, H), bg_color=BG).with_duration(duration)


def draw_timeline_step(layer: Image.Image, y: int, n: str, title: str, detail: str) -> None:
    d = ImageDraw.Draw(layer)
    d.ellipse((145, y - 38, 221, y + 38), fill=rgba(GREEN_DEEP), outline=rgba(GOLD), width=4)
    draw_text(layer, (183, y), n, 30, WHITE, "bold", "mm", "ltr")
    draw_text(layer, (920, y - 12), title, 42, INK, "bold", "rm")
    draw_text(layer, (920, y + 27), detail, 27, MUTED, "medium", "rm")


def make_scene_4(duration: float) -> CompositeVideoClip:
    base = scene_base(4, "متابعة مستمرة، وقرار مدروس")
    d = ImageDraw.Draw(base)
    d.line((183, 402, 183, 690), fill=rgba(GOLD_MID, 255), width=5)
    step_layers = [new_layer() for _ in range(3)]
    draw_timeline_step(step_layers[0], 405, "1", "رعاية", "وفق خطة الدورة")
    draw_timeline_step(step_layers[1], 515, "2", "متابعة", "حالة ووزن بتاريخ المتابعة")
    draw_timeline_step(step_layers[2], 625, "3", "مراجعة", "بيانات واتفاق")

    question = new_layer()
    qd = ImageDraw.Draw(question)
    qd.rounded_rectangle((135, 705, 965, 790), radius=20, fill=rgba(GOLD_HI, 110), outline=rgba(GOLD_MID), width=3)
    draw_text(question, (920, 747), "دراسة بيع جزء من القطيع؟", 39, INK, "bold", "rm")

    caution = new_layer()
    cd = ImageDraw.Draw(caution)
    cd.rounded_rectangle((135, 802, 965, 844), radius=18, fill=rgba(GREEN_DEEP), outline=rgba(GREEN_DEEP), width=2)
    draw_text(caution, (550, 823), "القرار حسب الحالة والعقد والسوق؛ لا موعد ثابت", 27, WHITE, "medium")

    clips = [ImageClip(np.asarray(base.convert("RGB"))).with_duration(duration)]
    clips.append(build_media(SOURCE_SHEEP_2, 2.0, 9.5, duration))
    frame = new_layer(); draw_panel_frame(frame)
    clips.append(ImageClip(np.asarray(frame), transparent=True).with_duration(duration))
    for layer, start in zip(step_layers, (0.8, 5.5, 10.4)):
        add_reveal(clips, layer, start, duration)
    add_reveal(clips, question, 15.0, duration)
    add_reveal(clips, caution, 19.0, duration)
    return CompositeVideoClip(clips, size=(W, H), bg_color=BG).with_duration(duration)


def make_scene_5(duration: float) -> CompositeVideoClip:
    base = Image.new("RGBA", (W, H), rgba(BG))
    d = ImageDraw.Draw(base)
    draw_text(base, (1775, 72), "05 / 05", 28, MUTED, "bold", "mm", "ltr")
    brand.watermark(base, pos="bl", theme="light", alpha=205, with_emblem=True)
    # Use the already-transparent official lockup instead of keying the JPEG;
    # its clean alpha avoids the dark speckling seen on cream backgrounds.
    with Image.open(ROOT / "public" / "logo-full.png") as source_logo:
        full_logo = source_logo.convert("RGBA")
    logo_width = max(700, int(W * 0.36))  # B12: lockup >= 0.36 x canvas width.
    logo_height = round(logo_width * full_logo.height / full_logo.width)
    full_logo = full_logo.resize((logo_width, logo_height), Image.Resampling.LANCZOS)
    base.alpha_composite(full_logo, ((W - logo_width) // 2, 20))
    draw_text(base, (960, 783), "البيانات أولًا، والقرار بعدها", 60, INK, "black")
    draw_text(base, (960, 832), "النتائج والمخاطر تختلف حسب الدورة والعقد والسوق", 29, INK, "bold")

    risk = new_layer()
    draw_text(risk, (960, 868), "لا توجد نتيجة مالية مضمونة", 26, MUTED, "medium")

    cta = new_layer()
    d = ImageDraw.Draw(cta)
    d.rounded_rectangle((535, 888, 1385, 978), radius=30, fill=rgba(GREEN_DEEP), outline=rgba(GOLD), width=4)
    draw_text(cta, (960, 908), "تواصل معنا على واتساب", 24, WHITE, "bold")
    draw_text(cta, (960, 949), "01010154221", 37, WHITE, "black", "mm", "ltr")

    foot = new_layer()
    draw_text(foot, (960, 1028), "راجع التفاصيل وشروط الاتفاق قبل اتخاذ القرار", 25, MUTED, "medium")
    clips = [ImageClip(np.asarray(base.convert("RGB"))).with_duration(duration)]
    add_reveal(clips, risk, 6.5, duration)
    add_reveal(clips, cta, 10.5, duration)
    add_reveal(clips, foot, 14.5, duration)
    return CompositeVideoClip(clips, size=(W, H), bg_color=BG).with_duration(duration)


def write_ambient(path: Path, duration: float, sample_rate: int = 44100) -> None:
    """A very quiet, slow synthetic pad under narration; no lyrics or borrowed track."""
    n = int(sample_rate * duration)
    t = np.arange(n, dtype=np.float64) / sample_rate
    breath = 0.70 + 0.20 * np.sin(2 * np.pi * t / 19.0) + 0.10 * np.sin(2 * np.pi * t / 31.0 + 0.6)
    pad = (
        0.48 * np.sin(2 * np.pi * 110.00 * t)
        + 0.32 * np.sin(2 * np.pi * 164.81 * t + 0.3)
        + 0.20 * np.sin(2 * np.pi * 220.00 * t + 0.8)
        + 0.11 * np.sin(2 * np.pi * 329.63 * t + 0.4)
    ) * breath * 0.018
    fade_in = np.minimum(1.0, t / 1.8)
    fade_out = np.minimum(1.0, np.maximum(0.0, (duration - t) / 2.0))
    pad *= fade_in * fade_out
    left = np.clip(pad * 0.96, -0.9, 0.9)
    right = np.clip(pad * 1.04, -0.9, 0.9)
    stereo = np.column_stack((left, right))
    pcm = np.asarray(stereo * 32767, dtype="<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(sample_rate)
        f.writeframes(pcm.tobytes())


def build_audio(duration: float, starts: list[float]):
    voice_clips = []
    for path, start in zip(VOICE_FILES, starts):
        voice = AudioFileClip(str(path))
        AUDIO_CACHE.append(voice)
        voice = voice.with_start(start).with_effects([afx.AudioFadeIn(0.12), afx.AudioFadeOut(0.32)])
        voice_clips.append(voice)
    ambient_path = BUILD_DIR / "quiet-ambient.wav"
    write_ambient(ambient_path, duration)
    music = AudioFileClip(str(ambient_path)).with_volume_scaled(1.0)
    AUDIO_CACHE.append(music)
    # Bring the mixed narration to the project's -15 LUFS target while keeping
    # several dB of true-peak headroom (the previous mix measured -19.3 LUFS).
    return CompositeAudioClip([music, *voice_clips]).with_duration(duration).with_volume_scaled(1.48)


def storyboard() -> None:
    STORYBOARD.mkdir(parents=True, exist_ok=True)
    audio_lengths = []
    for path in VOICE_FILES:
        with AudioFileClip(str(path)) as a:
            audio_lengths.append(a.duration)
    durations = [x + 0.25 for x in audio_lengths]
    builders = [make_scene_1, make_scene_2, make_scene_3, make_scene_4, make_scene_5]
    for i, (builder, dur) in enumerate(zip(builders, durations), 1):
        clip = builder(dur)
        frame = Image.fromarray(clip.get_frame(max(0.0, dur - 0.1))).convert("RGB")
        frame.save(STORYBOARD / f"scene-{i:02d}.jpg", quality=93)
        clip.close()
        print(f"storyboard scene {i:02d}: {dur:.2f}s")


def render() -> None:
    for path in VOICE_FILES:
        if not path.exists():
            raise FileNotFoundError(f"Missing narration: {path}")
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    durations: list[float] = []
    starts: list[float] = []
    cursor = 0.0
    for path in VOICE_FILES:
        with AudioFileClip(str(path)) as a:
            starts.append(cursor)
            duration = a.duration + 0.25
            durations.append(duration)
            cursor += duration
    total = sum(durations)
    builders = [make_scene_1, make_scene_2, make_scene_3, make_scene_4, make_scene_5]
    scenes = [builder(dur) for builder, dur in zip(builders, durations)]
    video = concatenate_videoclips(scenes, method="compose").with_duration(total)
    audio = build_audio(total, starts)
    final = video.with_audio(audio)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temp_audio = BUILD_DIR / "mix.m4a"
    final.write_videofile(
        str(OUTPUT),
        fps=FPS,
        codec="libx264",
        audio_codec="aac",
        audio_bitrate="192k",
        audio_fps=44100,
        preset="medium",
        threads=4,
        temp_audiofile=str(temp_audio),
        remove_temp=True,
        ffmpeg_params=["-crf", "21", "-pix_fmt", "yuv420p", "-movflags", "+faststart"],
        logger="bar",
    )
    for clip in scenes:
        clip.close()
    final.close()
    video.close()
    for clip in AUDIO_CACHE:
        clip.close()
    AUDIO_CACHE.clear()
    for clip in VIDEO_CACHE.values():
        clip.close()
    VIDEO_CACHE.clear()
    print(f"Rendered: {OUTPUT} ({total:.2f}s)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--storyboard", action="store_true", help="render still previews only")
    args = ap.parse_args()
    if args.storyboard:
        storyboard()
    else:
        render()


if __name__ == "__main__":
    main()
