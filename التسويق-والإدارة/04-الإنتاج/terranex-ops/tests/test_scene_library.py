#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""اختبارات مكتبة المشاهد — بحث عربي، إزالة تكرار، storyboard من الفهرس، سلامة الفهرس.

التشغيل:  python3 -m unittest discover -s tests -p 'test_*.py' -v
لا شبكة ولا GPU. تفترض أن الفهرس scene-library/index.json مبني ومتتبع (01 + 04).
"""
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "engine"))
import scene_library as SL  # noqa: E402

INDEX_PRESENT = os.path.isfile(SL.INDEX)


@unittest.skipUnless(INDEX_PRESENT, "الفهرس غير مبني")
class TestSearch(unittest.TestCase):
    def setUp(self):
        self.idx = SL.load_index()

    def test_tokenize_sheep_on_scale(self):
        self.assertEqual(SL.tokenize("الخروف على الميزان"), {"sheep", "scale"})

    def test_tokenize_best_weight_shot(self):
        self.assertEqual(SL.tokenize("أفضل لقطة وزن للخروف"), {"sheep", "scale"})

    def test_tokenize_english(self):
        self.assertEqual(SL.tokenize("sheep weighing"), {"sheep", "scale"})

    def test_acceptance_query_returns_real_scene(self):
        res = SL.search("الخروف على الميزان", k=3)
        self.assertTrue(res)
        top = res[0]
        self.assertEqual(top["scene_id"], "s04-02")
        self.assertEqual((top["start"], top["end"]), (4.0, 11.0))
        # مسار المصدر حقيقي موجود (غير مختلق)
        self.assertTrue(os.path.isfile(os.path.join(SL.REPO, top["source_path"])))
        self.assertTrue(os.path.isfile(os.path.join(SL.REPO, top["preview"])))

    def test_best_weight_query_top(self):
        res = SL.search("أفضل لقطة وزن للخروف", k=1)
        self.assertEqual(res[0]["scene_id"], "s04-02")

    def test_unusable_excluded_by_default(self):
        res = SL.search("شخص وجه", k=20)
        self.assertTrue(all(r["scene_id"] not in {"s01-01", "s01-05", "s01-06", "s01-09"} for r in res))

    def test_no_match_returns_empty(self):
        self.assertEqual(SL.search("طبخ مكرونة", k=5), [])

    def test_feeding_query(self):
        res = SL.search("تغذية الأبقار", k=3)
        self.assertTrue(res)
        self.assertIn("feeding", res[0]["matched_tags"])


@unittest.skipUnless(INDEX_PRESENT, "الفهرس غير مبني")
class TestStoryboardFromIndex(unittest.TestCase):
    def setUp(self):
        self.idx = SL.load_index()
        self.by_id = {s["scene_id"]: s for s in self.idx["scenes"]}
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT)

    def tearDown(self):
        self.tmp.cleanup()

    def test_timings_come_from_index_not_hardcoded(self):
        out = os.path.join(self.tmp.name, "spec.json")
        spec = SL.storyboard(["s04-02", "s01-02"], out)
        for clip in spec["clips"]:
            ref = self.by_id[clip["scene_id"]]
            self.assertEqual(clip["start"], ref["start"])
            self.assertEqual(clip["end"], ref["end"])
        self.assertTrue(spec["_library_derived"])

    def test_caption_windows_derived_from_durations(self):
        out = os.path.join(self.tmp.name, "spec.json")
        spec = SL.storyboard(["s01-02", "s04-02"], out, captions=["أ", "ب"])
        d0 = self.by_id["s01-02"]["end"] - self.by_id["s01-02"]["start"]
        d1 = self.by_id["s04-02"]["end"] - self.by_id["s04-02"]["start"]
        self.assertAlmostEqual(spec["captions"][0]["to"], round(d0, 3), places=3)
        self.assertAlmostEqual(spec["captions"][1]["to"] - spec["captions"][1]["from"], round(d1, 3), places=3)

    def test_treatment_from_scene_metadata(self):
        out = os.path.join(self.tmp.name, "spec.json")
        spec = SL.storyboard(["s04-02"], out)
        self.assertTrue(spec["clips"][0].get("proof_bar"))
        self.assertIn("crop", spec["clips"][0])

    def test_unknown_scene_rejected(self):
        with self.assertRaises(SystemExit):
            SL.storyboard(["s99-99"], os.path.join(self.tmp.name, "x.json"))

    def test_unusable_scene_rejected(self):
        with self.assertRaises(SystemExit):
            SL.storyboard(["s01-01"], os.path.join(self.tmp.name, "x.json"))


@unittest.skipUnless(INDEX_PRESENT, "الفهرس غير مبني")
class TestIndexIntegrity(unittest.TestCase):
    def setUp(self):
        self.idx = SL.load_index()

    def test_sources_have_sha256_and_real_paths(self):
        for sid, s in self.idx["sources"].items():
            self.assertEqual(len(s["sha256"]), 64)
            self.assertTrue(os.path.isfile(os.path.join(SL.REPO, s["path"])), sid)

    def test_no_duplicate_sha256(self):
        hashes = [s["sha256"] for s in self.idx["sources"].values()]
        self.assertEqual(len(hashes), len(set(hashes)))

    def test_scenes_reference_valid_sources_and_previews(self):
        for s in self.idx["scenes"]:
            self.assertIn(s["source_id"], self.idx["sources"])
            self.assertLess(s["start"], s["end"])
            self.assertTrue(os.path.isfile(os.path.join(SL.REPO, s["preview"])), s["scene_id"])

    def test_sources_git_tracked_restorable(self):
        # 01 و04 متتبعان في git → قابلان للاستعادة في جلسة جديدة
        for sid in ("src-01", "src-04"):
            self.assertTrue(self.idx["sources"][sid]["git_tracked"])

    def test_ingest_dedup_is_noop(self):
        # إعادة استيعاب 01 (موجود بنفس SHA-256) لا تضيف مصدرًا جديدًا
        before = len(self.idx["sources"])
        p = os.path.join(SL.REPO, self.idx["sources"]["src-01"]["path"])
        added = SL.ingest([p])
        self.assertEqual(added, [])
        self.assertEqual(len(SL.load_index()["sources"]), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
