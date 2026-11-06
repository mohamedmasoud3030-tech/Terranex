#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""اختبار انحدار لمصفوفة الدوران: المقاس المعروض لا المقاس المُرمّز.

سبب الاختبار: ٢٠ من ٣٠ فيديو WhatsApp في فروع الرفع تحمل displaymatrix ‎-90°‎.
الاعتماد على المقاس المُرمّز صنّفها أفقية خطأً، وكاد يبني إعلانًا أفقيًا من مادة رأسية.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from archive_audit import display_geometry, probe, IMAGE_EXT  # noqa: E402


class TestDisplayGeometry(unittest.TestCase):
    def test_no_rotation_keeps_coded(self):
        self.assertEqual(display_geometry(480, 848, "Video: h264 ... 480x848"), (480, 848, 0))

    def test_minus_90_swaps_to_portrait(self):
        err = "  Side data list:\n  Display Matrix: rotation of -90.00 degrees\n"
        self.assertEqual(display_geometry(1024, 576, err), (576, 1024, 270))

    def test_plus_90_swaps_to_portrait(self):
        err = "Display Matrix: rotation of 90.00 degrees"
        self.assertEqual(display_geometry(848, 480, err), (480, 848, 90))

    def test_180_keeps_dimensions(self):
        err = "Display Matrix: rotation of 180.00 degrees"
        self.assertEqual(display_geometry(1024, 576, err), (1024, 576, 180))

    def test_side_data_rotation_field(self):
        self.assertEqual(display_geometry(848, 480, "rotation : -90.00"), (480, 848, 270))

    def test_unknown_geometry_is_safe(self):
        self.assertEqual(display_geometry(None, None, "no video"), (None, None, 0))

    def test_true_landscape_is_not_rotated(self):
        # gh-a20 هو الفيديو الأفقي الحقيقي الوحيد في الدفعة
        self.assertEqual(display_geometry(848, 480, "Video: h264 ... 848x480"), (848, 480, 0))

    def test_probe_reports_both_geometries_on_real_file(self):
        """يتطلب نسخة عمل حقيقية؛ يتخطى بأمان إن لم تكن موجودة (النسخ غير ملتزَمة في Git)."""
        root = os.path.dirname(os.path.abspath(__file__))
        import json
        mani = os.path.join(root, "github-branches", "manifest.json")
        if not os.path.isfile(mani):
            self.skipTest("manifest absent")
        assets = json.load(open(mani, encoding="utf-8"))["assets"]
        rotated = next((a for a in assets if "7.21.14 AM (1)" in a["file_name"]
                        and a["file_name"].lower().endswith(".mp4")), None)
        if rotated is None or not os.path.isfile(rotated["working_copy"]):
            self.skipTest("rotated sample absent")
        p = probe(rotated["working_copy"])
        self.assertEqual((p["coded_width"], p["coded_height"]), (1024, 576))
        self.assertEqual((p["width"], p["height"]), (576, 1024))
        self.assertEqual(p["rotation_degrees"], 270)


if __name__ == "__main__":
    unittest.main(verbosity=2)
