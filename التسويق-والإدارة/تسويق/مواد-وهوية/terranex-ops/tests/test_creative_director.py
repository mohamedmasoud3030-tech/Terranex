#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Creative Director v1.1 — brief/JSON authoring, security, revisions, voice gates."""
import json
import math
import os
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
import creative_store as CS
import qa_video

REQ = ("اعمل إعلان 20 ثانية يوضح إننا بنتابع الحيوانات على أرض الواقع، بأسلوب مؤسسي احترافي، "
       "ولقطات متنوعة، وتعليق صوتي مصري هادي، وخاتمة فيها دعوة للتواصل.")
FEED_REQ = "اعمل إعلان 15 ثانية عن تغذية الأبقار في المزرعة، بأسلوب هادي، ولقطات حقيقية، وخاتمة فيها دعوة للتواصل."
WEIGHT_REQ = "اعمل إعلان 18 ثانية عن الوزن الحقلي للخروف، بأسلوب مؤسسي، ولقطات متنوعة، وتعليق صوتي مصري هادي، وخاتمة فيها دعوة للتواصل."
REVISE = "غيّر البداية، قلل لقطة الوزن، وقدم التغذية"


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


def _transcript(phrases):
    return {"verification_method": "human-reviewed", "reviewer": "unit-test",
            "approval_note": "إذن اختبار", "ai_generated": False,
            "phrases": [{"text": p["text"]} for p in phrases]}


class TestBrief(unittest.TestCase):
    def test_parse_egyptian_brief(self):
        b = CD.parse_brief(REQ)
        self.assertEqual(b["topic"], "field-followup")
        self.assertEqual(b["duration_sec"], 20.0)
        self.assertIn("مؤسسي", b["style"])
        self.assertTrue(b["voice"]["requested"])
        self.assertIsNotNone(b["cta"])

    def test_three_requests_choose_different_topics(self):
        self.assertEqual(CD.parse_brief(REQ)["topic"], "field-followup")
        self.assertEqual(CD.parse_brief(FEED_REQ)["topic"], "feeding")
        self.assertEqual(CD.parse_brief(WEIGHT_REQ)["topic"], "weight")

    def test_arabic_digits(self):
        self.assertEqual(CD.parse_brief("إعلان ٢٠ ثانية عن متابعة الحيوانات في المزرعة")["duration_sec"], 20.0)

    def test_missing_duration_rejected(self):
        with self.assertRaises(ValueError):
            CD.parse_brief("اعمل إعلان عن متابعة الحيوانات")

    def test_unsupported_topic_rejected(self):
        with self.assertRaises(ValueError):
            CD.parse_brief("اعمل إعلان 20 ثانية عن الطبخ")


class TestSecurity(unittest.TestCase):
    def test_project_id_traversal_rejected(self):
        for bad in ("../evil", "a/b", "..", "A_bad", "-lead", "x" * 80):
            with self.assertRaises(ValueError):
                CS.ProjectStore(bad)

    def test_store_file_allowlist(self):
        with tempfile.TemporaryDirectory() as td:
            store = CS.ProjectStore("safe-proj", td)
            with self.assertRaises(ValueError):
                store.path("../outside.json")
            with self.assertRaises(ValueError):
                store.path("voice-input.exe")
            self.assertTrue(str(store.path(CS.SPEC)).startswith(td))

    def test_measure_phrases_uses_stdin_not_filename_argument(self):
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "-i.wav")
            _wav(p, [(0.2, 1.0), (2.0, 1.0)])
            windows = CD.measure_phrases(p, 2)
            self.assertEqual(len(windows), 2)

    def test_render_and_attach_do_not_accept_arbitrary_paths(self):
        import inspect
        self.assertNotIn("out_path", inspect.signature(CD.render_project).parameters)
        self.assertNotIn("audio_path", inspect.signature(CD.attach_voice).parameters)
        self.assertNotIn("original_video", inspect.signature(CD.prove_relocation).parameters)


class TestLibraryAndPlan(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.idx = CD.load_index()
        cls.brief = CD.parse_brief(REQ)

    def test_index_restorable(self):
        self.assertEqual(CD.validate_index(self.idx), [])

    def test_ranking_excludes_unusable_and_persons(self):
        ranked = CD.rank_candidates(self.idx, self.brief)
        by_id = {s["scene_id"]: s for s in self.idx["scenes"]}
        for r in ranked:
            sc = by_id[r["scene_id"]]
            self.assertTrue(sc["usable"])
            self.assertNotIn("person", sc["tags"])
            self.assertNotIn("endcard", sc["tags"])

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
            self.assertGreaterEqual(shot["source_start"], sc["start"] - CD.TOL)
            self.assertLessEqual(shot["source_end"], sc["end"] + CD.TOL)

    def test_spec_relative_and_valid(self):
        sched = CD.select_and_schedule(self.idx, self.brief)
        with tempfile.TemporaryDirectory() as td:
            spec = CD.build_spec(self.idx, self.brief, sched, os.path.join(td, "spec.json"))
            CD.validate_plan(self.idx, self.brief, sched, spec)
            for c in spec["clips"]:
                self.assertFalse(os.path.isabs(c["path"]))
            self.assertTrue(spec["visual_draft"])

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


class TestCreativeJSON(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.proj = CD.create_project(FEED_REQ, project_id="creative-proj", projects_root=self.td.name)
        self.idx = CD.load_index()

    def tearDown(self):
        self.td.cleanup()

    def _creative(self):
        return {
            "schema_version": 1, "topic": "feeding", "note": "بداية من الحقل ثم التغذية",
            "hook": {"text": "من الأرض… للعلف.", "duration_sec": 1.5},
            "endcard_sec": 3.0,
            "shots": [
                {"scene_id": "s01-07", "role": "farm-open", "text": "من أرض المزرعة.", "duration_sec": 1.867},
                {"scene_id": "s01-08", "role": "feeding-close", "text": "العلف قدّام عينك.", "duration_sec": 2.033},
                {"scene_id": "s01-03", "role": "herd", "text": "والحظيرة بتتغذى.", "duration_sec": 1.5},
                {"scene_id": "s04-02", "role": "followup", "text": "ومتابعة على أرض الواقع.", "duration_sec": 6.6},
            ],
            "cta": {"text": "للتفاصيل… كلمنا على واتساب."},
            "endcard": {"headline": "ملك حقيقي", "subtitle": "ومتابعة بعينك",
                        "cta": "واتساب 01010154221", "disclosure": CD.SILENT_DISCLOSURE},
        }

    def test_apply_creative_changes_plan_and_versions(self):
        creative = self._creative()
        r = CD.apply_creative("creative-proj", creative, projects_root=self.td.name)
        self.assertEqual(r["version"], 2)
        self.assertEqual(r["plan"]["selected_scene_ids"], ["s01-07", "s01-08", "s01-03", "s04-02"])
        self.assertEqual(r["plan"]["authoring_mode"], "arena-json")
        self.assertNotEqual(r["plan"]["schedule"]["hook"], self.proj["plan"]["schedule"]["hook"])

    def test_creative_rejects_bad_scene(self):
        creative = self._creative()
        creative["shots"][0]["scene_id"] = "s99-99"
        with self.assertRaises(ValueError):
            CD.apply_creative("creative-proj", creative, projects_root=self.td.name)

    def test_creative_rejects_bad_duration(self):
        creative = self._creative()
        creative["shots"][0]["duration_sec"] = 5.0
        with self.assertRaises(ValueError):
            CD.apply_creative("creative-proj", creative, projects_root=self.td.name)

    def test_creative_rejects_banned_text(self):
        creative = self._creative()
        creative["hook"]["text"] = "عائد مضمون 30%"
        with self.assertRaises(ValueError):
            CD.apply_creative("creative-proj", creative, projects_root=self.td.name)

    def test_creative_rejects_unknown_fields(self):
        creative = self._creative()
        creative["color"] = "#FF0000"
        with self.assertRaises(ValueError):
            CD.apply_creative("creative-proj", creative, projects_root=self.td.name)


class TestMemoryAndRevision(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.proj = CD.create_project(REQ, project_id="rev-proj", projects_root=self.td.name)

    def tearDown(self):
        self.td.cleanup()

    def test_create_reload(self):
        loaded = CD.load_project("rev-proj", projects_root=self.td.name)
        self.assertEqual(loaded["memory"]["current_version"], 1)
        self.assertTrue(loaded["store"].exists(CS.STORYBOARD))

    def test_natural_revision_changes_plan_and_spec(self):
        before = self.proj["plan"]["selected_scene_ids"]
        r = CD.revise_project("rev-proj", REVISE, projects_root=self.td.name)
        after = r["plan"]["selected_scene_ids"]
        self.assertEqual(r["version"], 2)
        self.assertNotEqual(before, after)
        self.assertNotEqual(r["plan"]["schedule"]["hook"], self.proj["plan"]["schedule"]["hook"])
        self.assertEqual(after[1], "s01-08")
        self.assertTrue(any(s["scene_id"] == "s04-02" and s["planned_duration"] < 4.0
                            for s in r["plan"]["schedule"]["shots"]))
        self.assertTrue(r["spec"]["visual_draft"])

    def test_rollback_restores_previous_version(self):
        before = self.proj["plan"]["selected_scene_ids"]
        CD.revise_project("rev-proj", REVISE, projects_root=self.td.name)
        mem = CD.rollback_project("rev-proj", 1, projects_root=self.td.name)
        self.assertEqual(mem["current_version"], 1)
        loaded = CD.load_project("rev-proj", projects_root=self.td.name)
        self.assertEqual(loaded["plan"]["selected_scene_ids"], before)
        self.assertEqual(len(mem["versions"]), 2)

    def test_unsupported_revision_rejected(self):
        with self.assertRaises(ValueError):
            CD.revise_project("rev-proj", "اعمل حاجة حلوة", projects_root=self.td.name)


class TestVoiceSync(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.proj = CD.create_project(REQ, project_id="voice-proj", projects_root=self.td.name)
        self.store = self.proj["store"] if "store" in self.proj else CS.ProjectStore("voice-proj", self.td.name)
        self.n = len(self.proj["plan"]["schedule"]["voice_phrases"])
        self.segs = [(0.2, 1.5), (2.5, 1.5), (5.0, 1.0), (7.0, 1.0), (9.0, 1.0), (11.0, 1.5), (14.0, 2.0)]

    def tearDown(self):
        self.td.cleanup()

    def _asset(self):
        p = self.store.path("voice-input.wav")
        _wav(str(p), self.segs)
        return p

    def test_attach_requires_matching_human_transcript(self):
        self._asset()
        self.store.write_json(CS.VOICE_TRANSCRIPT, _transcript(self.proj["plan"]["schedule"]["voice_phrases"]))
        spec = CD.attach_voice("voice-proj", "إذن اختبار", projects_root=self.td.name)
        self.assertFalse(spec["visual_draft"])
        self.assertEqual(spec["_caption_timing_source"], "measured-energy+approved-transcript")
        self.assertEqual(len(spec["captions"]), self.n)

    def test_attach_rejects_transcript_mismatch(self):
        self._asset()
        tr = _transcript(self.proj["plan"]["schedule"]["voice_phrases"])
        tr["phrases"][0]["text"] = "نص مختلف تمامًا"
        self.store.write_json(CS.VOICE_TRANSCRIPT, tr)
        with self.assertRaises(ValueError):
            CD.attach_voice("voice-proj", "إذن اختبار", projects_root=self.td.name)

    def test_attach_rejects_energy_without_transcript(self):
        self._asset()
        with self.assertRaises(ValueError):
            CD.attach_voice("voice-proj", "إذن اختبار", projects_root=self.td.name)

    def test_attach_rejects_phrase_count_mismatch(self):
        p = self.store.path("voice-input.wav")
        _wav(str(p), [(0.2, 1.5), (2.5, 1.5), (5.0, 1.0)])
        self.store.write_json(CS.VOICE_TRANSCRIPT, _transcript(self.proj["plan"]["schedule"]["voice_phrases"]))
        with self.assertRaises(ValueError):
            CD.attach_voice("voice-proj", "إذن اختبار", projects_root=self.td.name)


class TestReviewGates(unittest.TestCase):
    def test_silent_draft_never_publication_ready(self):
        spec = {"visual_draft": True, "voice": {}}
        qa = {"pass": True}
        cr = {"score": 100, "hard": []}
        pub = CD.publication_readiness(spec, qa, cr)
        self.assertFalse(pub["ready"])
        self.assertEqual(pub["decision"], "غير جاهز للنشر")
        self.assertTrue(pub["text_success"])
        self.assertTrue(pub["technical_success"])

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
            self.assertTrue(any("مسودة" in w for w in draft["warns"]))
            final = qa_video.qa(v, "reels", visual_draft=False)
            self.assertFalse(final["pass"])


if __name__ == "__main__":
    unittest.main()
