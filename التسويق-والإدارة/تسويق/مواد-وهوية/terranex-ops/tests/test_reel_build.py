#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""اختبارات reel_build —قصّ آمن، إخفاء العلامة، تزامن الكابشن، أمان المسارات، توافق القوالب.

التشغيل:  python3 -m unittest discover -s tests -p 'test_*.py' -v
لا شبكة ولا GPU — ffmpeg عبر imageio_ffmpeg فقط. لا يلمس كود التطبيق.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "engine"))
import reel_build as R  # noqa: E402
import imageio_ffmpeg  # noqa: E402

FF = imageio_ffmpeg.get_ffmpeg_exe()
CAMP = os.path.join(ROOT, "output", "campaigns", "حملة-الإعلان-المؤسسي-ممول-١")


def _touch(path, data=b"x"):
    with open(path, "wb") as fh:
        fh.write(data)


def make_clip(path, boxes, w=720, h=1280, dur=1.0):
    """لقطة صناعية: خلفية سوداء + صناديق بيضاء في مناطق محددة (لمحاكاة موضوع/علامة)."""
    vf = ",".join(f"drawbox=x={x}:y={y}:w={bw}:h={bh}:color=white:t=fill"
                  for (x, y, bw, bh) in boxes)
    subprocess.run([FF, "-y", "-v", "error", "-f", "lavfi",
                    "-i", f"color=c=black:s={w}x{h}:d={dur}:r=30",
                    "-vf", vf, "-c:v", "libx264", "-pix_fmt", "yuv420p", path], check=True)


def frame_of(path, t=0.2):
    out = path + ".frame.png"
    subprocess.run([FF, "-y", "-v", "error", "-ss", str(t), "-i", path,
                    "-frames:v", "1", out], check=True)
    return np.asarray(Image.open(out).convert("RGB"))


def white_mask(a):
    return (a[..., 0] > 200) & (a[..., 1] > 200) & (a[..., 2] > 200)


class TestPathSafety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT)
        self.root = os.path.join(self.tmp.name, "root")
        os.makedirs(self.root)
        self.inside = os.path.join(self.root, "ok.mp4")
        _touch(self.inside)
        self.outside = os.path.join(self.tmp.name, "secret.mp4")
        _touch(self.outside, b"secret")

    def tearDown(self):
        self.tmp.cleanup()

    def test_legit_inside_root(self):
        self.assertEqual(R._safe_input_path(self.inside, self.root), os.path.realpath(self.inside))

    def test_traversal_rejected(self):
        evil = os.path.join(self.root, "..", "secret.mp4")
        with self.assertRaises(SystemExit):
            R._safe_input_path(evil, self.root)

    def test_symlink_escape_rejected(self):
        link = os.path.join(self.root, "link.mp4")
        os.symlink(self.outside, link)
        with self.assertRaises(SystemExit):
            R._safe_input_path(link, self.root)

    def test_symlink_within_root_allowed(self):
        link = os.path.join(self.root, "good_link.mp4")
        os.symlink(self.inside, link)
        self.assertEqual(R._safe_input_path(link, self.root), os.path.realpath(self.inside))

    def test_option_injection_rejected(self):
        evil = os.path.join(self.root, "-evil.mp4")
        _touch(evil)
        with self.assertRaises(SystemExit):
            R._safe_input_path(evil, self.root)

    def test_missing_rejected(self):
        with self.assertRaises(SystemExit):
            R._safe_input_path(os.path.join(self.root, "nope.mp4"), self.root)

    def test_prefix_sibling_rejected(self):
        # جذر شقيق يبدأ بنفس البادئة يجب ألا يُقبل (commonpath لا startswith)
        sib = os.path.join(self.tmp.name, "root-evil")
        os.makedirs(sib)
        f = os.path.join(sib, "a.mp4"); _touch(f)
        with self.assertRaises(SystemExit):
            R._safe_input_path(f, self.root)

    def test_real_footage_relative_resolves(self):
        # مسار نسبي حقيقي داخل جذر التسويق ما زال يعمل (لا كسر للاستخدام الحالي)
        vid = os.path.join(ROOT, "..", "..", "فيديوهات-جاهزة-للنشر", "01-بومو-الشركة-الرئيسي.mp4")
        got = R._safe_input_path(vid, R.MARKETING_ROOT)
        self.assertTrue(os.path.isfile(got))


class TestSafeCrop(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT)

    def tearDown(self):
        self.tmp.cleanup()

    def test_vf_crop_fractions(self):
        vf = R._clip_vf({"crop": {"bottom": 0.42}})
        self.assertIn("crop=iw*1.0000:ih*0.5800", vf)
        self.assertIn("unsharp", vf)

    def test_vf_legacy_zoom_preserved(self):
        vf = R._clip_vf({"hide_burnt_logo": True, "crop_bottom_pct": 0.34})
        self.assertIn("scale=", vf)
        self.assertNotIn("crop=iw*", vf)  # ليس قصّ نسبي بل التكبير القديم

    def test_crop_keeps_subject_drops_watermark(self):
        src = os.path.join(self.tmp.name, "src.mp4")
        # موضوع أعلى (y100-300) + علامة أسفل (y1100-1250)
        make_clip(src, [(200, 100, 300, 200), (200, 1100, 300, 150)])
        out = os.path.join(self.tmp.name, "cropped.mp4")
        vf = R._clip_vf({"crop": {"bottom": 0.42}})
        subprocess.run([FF, "-y", "-v", "error", "-i", src, "-vf", vf,
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", out], check=True)
        a = frame_of(out)
        wm = white_mask(a)
        h = a.shape[0]
        top_white = wm[: h // 2].sum()
        bot_white = wm[h // 2:].sum()
        self.assertGreater(top_white, 1000)          # الموضوع نجا
        self.assertLess(bot_white, top_white * 0.05)  # العلامة أُزيلت
        self.assertEqual((a.shape[1], a.shape[0]), (1080, 1920))


class TestWatermarkHiding(unittest.TestCase):
    def test_proofbar_opaque_over_watermark_transparent_over_animal(self):
        lay = R.proofbar_layer()
        alpha = np.asarray(lay.getchannel("A"))
        h = alpha.shape[0]
        self.assertEqual(int(alpha[int(h * 0.63), 540]), 255)  # فوق العلامة (~63%) معتم
        self.assertEqual(int(alpha[int(h * 0.68), 540]), 255)
        self.assertEqual(int(alpha[int(h * 0.30), 540]), 0)    # فوق الحيوان (~30%) شفاف
        self.assertEqual(int(alpha[int(h * 0.15), 540]), 0)

    def test_proofbar_covers_watermark_not_animal(self):
        # فريم صناعي: علامة عند 63% + حيوان عند 30%
        base = Image.new("RGB", (R.W, R.H), (40, 40, 40))
        from PIL import ImageDraw
        d = ImageDraw.Draw(base)
        d.rectangle([300, int(R.H * 0.615), 780, int(R.H * 0.655)], fill=(255, 255, 255))  # علامة
        d.rectangle([400, int(R.H * 0.28), 680, int(R.H * 0.34)], fill=(255, 255, 255))    # حيوان
        comp = base.convert("RGBA")
        comp.alpha_composite(R.proofbar_layer())
        a = np.asarray(comp.convert("RGB"))
        # منطقة العلامة لم تعد بيضاء (غطّاها الشريط)
        wm = a[int(R.H * 0.615):int(R.H * 0.655), 300:780]
        self.assertLess(white_mask(wm).mean(), 0.02)
        # منطقة الحيوان ما زالت بيضاء (لم يغطّها الشريط)
        an = a[int(R.H * 0.28):int(R.H * 0.34), 400:680]
        self.assertGreater(white_mask(an).mean(), 0.95)


def speech_phrases(path, thr_db=-38.0, merge_gap=0.30):
    """استخراج حدود الجمل الصوتية من طاقة التعليق (بدون whisper)."""
    p = subprocess.run([FF, "-v", "error", "-i", path, "-ac", "1", "-ar", "16000",
                        "-f", "s16le", "-"], capture_output=True)
    a = np.frombuffer(p.stdout, dtype=np.int16).astype(np.float32) / 32768
    win = 800  # 50ms
    n = len(a) // win
    rms = np.array([np.sqrt(np.mean(a[i * win:(i + 1) * win] ** 2)) for i in range(n)])
    db = 20 * np.log10(rms + 1e-9)
    segs, cur, start = [], None, 0
    for i, v in enumerate(db):
        s = v > thr_db
        if cur is None:
            cur, start = s, i
        elif s != cur:
            segs.append((cur, start * 0.05, i * 0.05)); cur, start = s, i
    segs.append((cur, start * 0.05, n * 0.05))
    speech = [(a0, a1) for s, a0, a1 in segs if s and a1 - a0 > 0.10]
    merged = []
    for a0, a1 in speech:
        if merged and a0 - merged[-1][1] < merge_gap:
            merged[-1] = (merged[-1][0], a1)
        else:
            merged.append((a0, a1))
    return merged


class TestCaptionSync(unittest.TestCase):
    def test_captions_contain_vo_phrases(self):
        vo = os.path.join(CAMP, "vo-09b.mp3")
        spec = os.path.join(CAMP, "spec-09b-v2.json")
        if not (os.path.isfile(vo) and os.path.isfile(spec)):
            self.skipTest("vo/spec غير موجودين")
        phrases = speech_phrases(vo)
        self.assertGreaterEqual(len(phrases), 4)
        sc = json.load(open(spec, encoding="utf-8"))
        windows = [(0.0, float(sc["hook_sec"]))] + [(float(c["from"]), float(c["to"])) for c in sc["captions"]]
        # كل نافذة كابشن/هوك تحتوي جملة صوتية كاملة واحدة على الأقل
        for w0, w1 in windows:
            contained = [p for p in phrases if p[0] >= w0 - 0.05 and p[1] <= w1 + 0.05]
            self.assertTrue(contained, f"النافذة [{w0},{w1}] لا تحتوي جملة صوتية — عدم تزامن")
        # الجملة الأخيرة تقع فوق إطار الختام
        end_start = sum(c["end"] - c["start"] for c in sc["clips"])
        total = end_start + float(sc["endcard_sec"])
        last = phrases[-1]
        self.assertGreaterEqual(last[0], end_start - 0.2)
        self.assertLessEqual(last[1], total)


class TestBackwardCompat(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT)
        self.cwd = os.getcwd()
        os.chdir(ROOT)  # حتى يكون مجلد الاختبار داخل جذر الـspec المسموح

    def tearDown(self):
        os.chdir(self.cwd)
        self.tmp.cleanup()

    def test_legacy_spec_still_builds(self):
        src = os.path.join(self.tmp.name, "src.mp4")
        make_clip(src, [(200, 100, 300, 200)], dur=1.0)
        spec = {
            "title": "legacy", "on_screen_persons": [], "consent_persons": [],
            "clips": [{"path": os.path.basename(src), "start": 0.0, "end": 1.0,
                       "hide_burnt_logo": True, "crop_bottom_pct": 0.34}],
            "hook": "رأس حقيقي", "hook_sec": 0.5, "endcard_sec": 0.5,
            "captions": [{"from": 0.5, "to": 0.9, "text": "ملك حقيقي"}],
        }
        sp = os.path.join(self.tmp.name, "spec.json")
        with open(sp, "w", encoding="utf-8") as fh:
            json.dump(spec, fh, ensure_ascii=False)
        out = os.path.join(self.tmp.name, "out.mp4")
        r = R.build(sp, None, out)
        self.assertTrue(os.path.isfile(out))
        self.assertEqual(r["clips"], 1)
        a = frame_of(out, t=0.2)
        self.assertEqual((a.shape[1], a.shape[0]), (1080, 1920))


if __name__ == "__main__":
    unittest.main(verbosity=2)


class TestAD1Options(unittest.TestCase):
    """خيارات AD-1: بلا حدّة صناعية، تحجيم lanczos، شريط كابشن قابل للضبط، صور ثابتة."""

    def test_sharpen_off_removes_unsharp(self):
        vf = R._clip_vf({"crop": {"top": 0.0}, "sharpen": False})
        self.assertNotIn("unsharp", vf)

    def test_sharpen_default_unchanged(self):
        self.assertIn("unsharp", R._clip_vf({"crop": {"top": 0.0}}))

    def test_lanczos_flag_applied(self):
        self.assertIn("flags=lanczos", R._clip_vf({"crop": {}, "scale_flags": "lanczos"}))

    def test_unknown_scale_flag_ignored(self):
        vf = R._clip_vf({"crop": {}, "scale_flags": "bogus;rm -rf"})
        self.assertNotIn("flags=", vf)

    def test_caption_band_moves_but_stays_clamped(self):
        a = R.cap_layer("الوزن قدامك", 0.84)
        b = R.cap_layer("الوزن قدامك", 0.70)
        self.assertNotEqual(a.tobytes(), b.tobytes())
        self.assertEqual(R.cap_layer("x", 0.99).tobytes(), R.cap_layer("x", 0.90).tobytes())

    def test_image_extensions_recognised(self):
        self.assertIn(".jpg", R.IMAGE_EXT)
        self.assertIn(".jpeg", R.IMAGE_EXT)


class TestDeliveryCityConsentGate(unittest.TestCase):
    """B9 تظل مغلقة افتراضيًا ولا تُفتح إلا بتفويض توصيل صريح وموثق من المالك."""

    def test_city_blocked_by_default(self):
        import brand as B
        import critic
        city = B.CITY_BAN[0]
        with self.assertRaises(SystemExit):
            R.lint_text(f"حجز {city}")
        res = critic.check(f"فتح الحجز في {city}\n#TerraNex #خروف_برقي #ضاني_برقي")
        self.assertTrue(any(h["code"] == "B9" for h in res["hard"]))

    def test_delivery_city_requires_non_empty_note(self):
        self.assertFalse(R._delivery_city_authorized({}))
        self.assertFalse(R._delivery_city_authorized({"consent": {"allow_delivery_city": True}}))
        self.assertFalse(R._delivery_city_authorized({"consent": {"allow_delivery_city": True, "delivery_city_approval_note": "   "}}))
        self.assertTrue(R._delivery_city_authorized({
            "consent": {"allow_delivery_city": True, "delivery_city_approval_note": "طلب صريح من المالك"}
        }))

    def test_authorized_delivery_city_layers_and_critic(self):
        import brand as B
        import critic
        city = B.CITY_BAN[0]
        hk = R.hook_layer(f"فتح الحجز · {city}", allow_city=True)
        cp = R.cap_layer(f"توصيل {city}", 0.84, allow_city=True)
        ec = R.endcard_layer({"headline": city}, allow_city=True)
        self.assertEqual(hk.size, (1080, 1920))
        self.assertEqual(cp.size, (1080, 1920))
        self.assertEqual(ec.size, (1080, 1920))
        res = critic.check(
            f"فتح باب الحجز لمحافظة {city}\nربع برقي حر لباب البيت 01010154221\n#TerraNex #خروف_برقي #ضاني_برقي",
            allow_delivery_city=True,
        )
        self.assertEqual(res["hard"], [])
