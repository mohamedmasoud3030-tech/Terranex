#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""اختبارات Creative Director v1 — فهم الطلب، الفهرس، التوقيت، الذاكرة، الصوت، QA."""
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "engine"))

import creative_director as CD
import qa_video
import reel_build as R
import scene_library as SL

REQ = ("اعمل إعلان 20 ثانية يوضح إننا بنتابع الحيوانات على أرض الواقع، بأسلوب مؤسسي احترافي، "
       "ولقطات متنوعة، وتعليق صوتي مصري هادي، وخاتمة فيها دعوة للتواصل.")


def _wav(path, segments, sr=16000, total=20.0):
    n = int(total * sr)
    a = np.zeros(n, dtype=np.float32)
    for start, dur in segments:
        i0, i1 = int(start * sr), int((start + dur) * sr)
        t = np.arange(i1 - i0) / sr
        a[i0:i1] = 0.3 * np.sin(2 * math.pi * 220 * t)
    pcm = (a * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


class TestBrief(unittest.TestCase):
    def test_parse_egyptian_brief(self):
        b = CD.parse_brief(REQ)
        self.assertEqual(b["topic"], "field-followup")
        self.assertEqual(b["duration_sec"], 20.0)
        self.assertIn("مؤسسي", b["style"])
        self.assertTrue(b["voice"]["requested"])
        self.assertEqual(b["voice"]["language"], "ar-EG")
        self.assertIsNotNone(b["cta"])
        self.assertTrue(b["variety_requested"])

    def test_arabic_digits(self):
        b = CD.parse_brief("إعلان ٢٠ ثانية عن متابعة الحيوانات في المزرعة")
        self.assertEqual(b["duration_sec"], 20.0)

    def test_missing_duration_rejected(self):
        with self.assertRaises(ValueError):
            CD.parse_brief("اعمل إعلان عن متابعة الحيوانات")

    def test_unsupported_topic_rejected(self):
        with self.assertRaises(ValueError):
            CD.parse_brief("اعمل إعلان 20 ثانية عن الطبخ")


class TestLibraryAndPlan(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.idx = CD.load_index()
        cls.brief = CD.parse_brief(REQ)

    def test_index_restorable(self):
        self.assertEqual(CD.validate_index(self.idx), [])

    def test_ranking_excludes_unusable_and_persons(self):
        ranked = CD.rank_candidates(self.idx, self.brief)
        ids = {r["scene_id"] for r in ranked}
        by_id = {s["scene_id"]: s for s in self.idx["scenes"]}
        for sid in ids:
            sc = by_id[sid]
            self.assertTrue(sc["usable"])
            self.assertNotIn("person", sc["tags"])
            self.assertNotIn("endcard", sc["tags"])
        self.assertIn("s04-02", ids)

    def test_schedule_exact_duration_and_bounds(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        total = sum(s["planned_duration"] for s in sched["shots"]) + sched["endcard_sec"]
        self.assertAlmostEqual(total, self.brief["duration_sec"], places=2)
        by_id = {s["scene_id"]: s for s in self.idx["scenes"]}
        seen = set()
        for shot in sched["shots"]:
            self.assertNotIn(shot["scene_id"], seen)
            seen.add(shot["scene_id"])
            sc = by_id[shot["scene_id"]]
            self.assertTrue(sc["usable"])
            self.assertGreaterEqual(shot["source_start"], sc["start"] - CD.TOL)
            self.assertLessEqual(shot["source_end"], sc["end"] + CD.TOL)
            self.assertLess(shot["source_start"], shot["source_end"])

    def test_spec_relative_and_valid(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        with tempfile.TemporaryDirectory() as td:
            spec_path = os.path.join(td, "spec.json")
            spec = CD.build_spec(self.idx, self.brief, sched, spec_path)
            CD.validate_plan(self.idx, self.brief, sched, spec)
            for c in spec["clips"]:
                self.assertFalse(os.path.isabs(c["path"]))
                self.assertIn("scene_id", c)
            self.assertTrue(spec["visual_draft"])
            self.assertIn("مسودة", spec["endcard"]["disclosure"])

    def test_reject_invented_scene_id(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        with tempfile.TemporaryDirectory() as td:
            spec = CD.build_spec(self.idx, self.brief, sched, os.path.join(td, "spec.json"))
            sched["shots"][0]["scene_id"] = "s99-99"
            spec["clips"][0]["scene_id"] = "s99-99"
            with self.assertRaises(ValueError):
                CD.validate_plan(self.idx, self.brief, sched, spec)

    def test_reject_out_of_bounds_timing(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        with tempfile.TemporaryDirectory() as td:
            spec = CD.build_spec(self.idx, self.brief, sched, os.path.join(td, "spec.json"))
            sc = next(s for s in self.idx["scenes"] if s["scene_id"] == spec["clips"][0]["scene_id"])
            spec["clips"][0]["start"] = sc["start"] - 1.0
            with self.assertRaises(ValueError):
                CD.validate_plan(self.idx, self.brief, sched, spec)

    def test_reject_absolute_path(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        with tempfile.TemporaryDirectory() as td:
            spec = CD.build_spec(self.idx, self.brief, sched, os.path.join(td, "spec.json"))
            spec["clips"][0]["path"] = "/tmp/whatever.mp4"
            with self.assertRaises(ValueError):
                CD.validate_plan(self.idx, self.brief, sched, spec)

    def test_reject_over_duration(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        with tempfile.TemporaryDirectory() as td:
            spec = CD.build_spec(self.idx, self.brief, sched, os.path.join(td, "spec.json"))
            spec["clips"][0]["end"] += 5.0
            with self.assertRaises(ValueError):
                CD.validate_plan(self.idx, self.brief, sched, spec)

    def test_reject_unusable_scene(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        with tempfile.TemporaryDirectory() as td:
            spec = CD.build_spec(self.idx, self.brief, sched, os.path.join(td, "spec.json"))
            bad = next(s["scene_id"] for s in self.idx["scenes"] if not s["usable"])
            sched["shots"][0]["scene_id"] = bad
            spec["clips"][0]["scene_id"] = bad
            with self.assertRaises(ValueError):
                CD.validate_plan(self.idx, self.brief, sched, spec)


class TestMemory(unittest.TestCase):
    def test_create_reload_revise(self):
        with tempfile.TemporaryDirectory() as td:
            r = CD.create_project(REQ, project_id="test-proj", projects_root=td)
            pdir = r["project_dir"]
            for name in ("brief.json", "plan.json", "spec.json", "storyboard.png", "memory.json", "decisions.jsonl"):
                self.assertTrue(os.path.isfile(os.path.join(pdir, name)), name)
            loaded = CD.load_project("test-proj", projects_root=td)
            self.assertEqual(loaded["memory"]["project_id"], "test-proj")
            self.assertEqual(loaded["memory"]["selected_scene_ids"], r["plan"]["selected_scene_ids"])
            CD.revise_project("test-proj", "تعديل تجريبي", projects_root=td)
            again = CD.load_project("test-proj", projects_root=td)
            self.assertEqual(len(again["memory"]["revisions"]), 1)
            with open(os.path.join(pdir, "decisions.jsonl"), encoding="utf-8") as f:
                lines = f.read().strip().splitlines()
            self.assertGreaterEqual(len(lines), 2)


class TestVoiceSync(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.proj = CD.create_project(REQ, project_id="voice-proj", projects_root=self.td.name)
        self.n = len(self.proj["plan"]["schedule"]["voice_phrases"])

    def tearDown(self):
        self.td.cleanup()

    def test_measure_phrases(self):
        segs = [(0.2, 1.5), (2.5, 1.5), (5.0, 1.0), (7.0, 1.0), (9.0, 1.0), (11.0, 1.5), (14.0, 2.0)]
        p = os.path.join(self.td.name, "vo.wav")
        _wav(p, segs)
        windows = CD.measure_phrases(p, self.n)
        self.assertEqual(len(windows), self.n)
        for (x, y), (sx, d) in zip(windows, segs):
            self.assertAlmostEqual(x, sx, delta=0.15)
            self.assertAlmostEqual(y, sx + d, delta=0.15)

    def test_attach_voice_syncs_captions(self):
        segs = [(0.2, 1.5), (2.5, 1.5), (5.0, 1.0), (7.0, 1.0), (9.0, 1.0), (11.0, 1.5), (14.0, 2.0)]
        p = os.path.join(self.td.name, "vo.wav")
        _wav(p, segs)
        spec = CD.attach_voice("voice-proj", p, "إذن اختبار", projects_root=self.td.name)
        self.assertEqual(spec["_caption_timing_source"], "measured-energy")
        self.assertFalse(spec["visual_draft"])
        self.assertEqual(len(spec["captions"]), self.n)
        for cap, (sx, d) in zip(spec["captions"], segs):
            self.assertAlmostEqual(cap["from"], max(0.0, sx - 0.05), delta=0.2)
            self.assertAlmostEqual(cap["to"], sx + d + 0.05, delta=0.2)
        self.assertIn("voice", spec)
        self.assertTrue(spec["voice"]["sha256"])

    def test_attach_rejects_phrase_count_mismatch(self):
        p = os.path.join(self.td.name, "vo.wav")
        _wav(p, [(0.2, 1.5), (2.5, 1.5), (5.0, 1.0)])
        with self.assertRaises(ValueError):
            CD.attach_voice("voice-proj", p, "إذن اختبار", projects_root=self.td.name)

    def test_attach_rejects_missing_approval(self):
        p = os.path.join(self.td.name, "vo.wav")
        _wav(p, [(0.2, 1.5)])
        with self.assertRaises(ValueError):
            CD.attach_voice("voice-proj", p, "   ", projects_root=self.td.name)

    def test_attach_rejects_wrong_profile(self):
        p = os.path.join(self.td.name, "vo.wav")
        _wav(p, [(0.2, 1.5)])
        with self.assertRaises(ValueError):
            CD.attach_voice("voice-proj", p, "إذن", projects_root=self.td.name, profile_id="other")


class TestSilentQA(unittest.TestCase):
    def test_visual_draft_allows_silent_but_warns(self):
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        with tempfile.TemporaryDirectory() as td:
            v = os.path.join(td, "silent.mp4")
            subprocess.run([ff, "-y", "-v", "error", "-f", "lavfi", "-i",
                            "color=c=0x203040:s=540x960:r=30:d=4", "-c:v", "libx264",
                            "-pix_fmt", "yuv420p", v], check=True)
            draft = qa_video.qa(v, "reels", visual_draft=True)
            self.assertTrue(draft["pass"])
            self.assertTrue(draft["meta"].get("visual_draft"))
            self.assertTrue(any("مسودة" in w for w in draft["warns"]))
            final = qa_video.qa(v, "reels", visual_draft=False)
            self.assertFalse(final["pass"])
            self.assertTrue(any("صوتي" in f for f in final["fails"]))


class TestStoryboardPortability(unittest.TestCase):
    def test_library_storyboard_relative_paths(self):
        with tempfile.TemporaryDirectory() as td:
            out = os.path.join(td, "spec.json")
            SL.storyboard(["s01-02", "s04-02"], out, hook="", hook_sec=0.0, captions=["نص"], endcard_sec=3.0)
            with open(out, encoding="utf-8") as f:
                spec = json.load(f)
            for c in spec["clips"]:
                self.assertFalse(os.path.isabs(c["path"]))


if __name__ == "__main__":
    unittest.main()
