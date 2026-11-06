# -*- coding: utf-8 -*-
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "engine"))
import production_robot as B


class ProductionRobotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name)
        self.work = self.repo / "work"
        (self.repo/"raw").mkdir()
        self.entries = []
        for ident, tag, kind, status in [
            ("farm", "animals-clean", "video", "editorial-review-required"),
            ("weight", "weighing-activity", "video", "editorial-review-required"),
            ("slaughter", "slaughter-graphic", "video", "quarantined-not-for-ads"),
            ("packed", "packaged-meat", "image", "separate-campaign-review")]:
            p = self.repo/"raw"/(ident+(".mp4" if kind=="video" else ".jpg"))
            p.write_bytes((ident*10).encode())
            self.entries.append({"id": ident, "archive_path": "raw/"+p.name,
                                 "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
                                 "category": [tag], "kind": kind, "status": status,
                                 "duration_sec": 30 if kind=="video" else None,
                                 "quality": 0.8, "consent_required": False})
        self.manifest = self.repo/"manifest.json"
        self.manifest.write_text(json.dumps({"assets": self.entries}))
        self.assets = B.assets(self.manifest, self.work, self.repo)

    def tearDown(self):
        self.temp.cleanup()

    def test_missing_cutting_and_delivery_are_reported(self):
        plan = B.make_plan({"stages": ["farm", "cutting", "delivery"]}, self.assets)
        self.assertEqual([x["stage"] for x in plan["missing"]], ["cutting", "delivery"])
        self.assertFalse(plan["ready_for_render"])
        with self.assertRaises(B.Blocked):
            B.make_spec(plan, {})

    def test_no_unapproved_slaughter(self):
        p = B.make_plan({"stages": ["slaughter"]}, self.assets)
        self.assertIn("sensitive", p["missing"][0]["reason"])
        p = B.make_plan({"stages": ["slaughter"], "allow_sensitive_preview": True}, self.assets)
        self.assertEqual(p["review_needed"], ["slaughter"])
        self.assertFalse(p["publish_approved"])

    def test_cut_meat_photo_is_not_cutting_action(self):
        p = B.make_plan({"stages": ["cutting", "packing"], "allow_stills": True}, self.assets)
        self.assertEqual(p["missing"][0]["stage"], "cutting")
        self.assertEqual(p["shots"][1]["asset_id"], "packed")

    def test_no_slideshow_by_default(self):
        p = B.make_plan({"stages": ["packing"]}, self.assets)
        self.assertEqual(len(p["missing"]), 1)

    def test_plan_requires_visual_review(self):
        p = B.make_plan({"stages": ["weighing"]}, self.assets)
        self.assertFalse(p["ready_for_render"])
        self.assertEqual(p["review_needed"], ["weighing"])
        p = B.make_plan({"stages": ["weighing"], "choices": {
            "weighing": {"asset_id": "weight", "start": 2, "window_reviewed": True}}}, self.assets)
        self.assertTrue(p["ready_for_render"])
        s = B.make_spec(p, {})
        self.assertFalse(s["publish_approved"])
        self.assertEqual(s["clips"][0]["start"], 2)

    def test_upload_review_before_use(self):
        f = self.repo/"delivery.mp4"
        f.write_bytes(b"recorded-delivery")
        asset = B.ingest(f, "delivery", self.work)
        a = B.assets(self.manifest, self.work, self.repo)
        self.assertFalse(B.make_plan({"stages": ["delivery"]}, a)["ready_for_render"])
        B.review_upload(asset["id"], "Vehicle arrived and customer received order", 20, self.work)
        a = B.assets(self.manifest, self.work, self.repo)
        p = B.make_plan({"stages": ["delivery"]}, a)
        self.assertTrue(p["ready_for_render"])
        self.assertFalse(p["publish_approved"])

    def test_rejects_tampering(self):
        f = self.repo/"delivery.mp4"
        f.write_bytes(b"original")
        a = B.ingest(f, "delivery", self.work)
        Path(a["path"]).write_bytes(b"altered")
        with self.assertRaises(B.Blocked):
            B.review_upload(a["id"], "checked", 9, self.work)

    def test_invalid_briefs(self):
        for bad in ({"duration_seconds": 0}, {"stages": ["farm", "farm"]},
                    {"stages": ["nonexistent"]}):
            with self.assertRaises(B.Blocked):
                B.make_plan(bad, self.assets)

    def test_path_escape_rejected(self):
        with self.assertRaises(B.Blocked):
            B.confined(self.repo.parent/"outside.mp4", self.repo)


if __name__ == "__main__":
    unittest.main()
