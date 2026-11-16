# -*- coding: utf-8 -*-
"""B13 (قرار المالك 2026-11-16): رفض الأسعار في نصوص الإعلانات الجديدة
مع الحفاظ على السجلات السعرية التاريخية دون حذفها."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine"))
import critic  # noqa: E402

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
MARKETING = os.path.abspath(os.path.join(TESTS_DIR, "..", "..", ".."))


class PriceBanTests(unittest.TestCase):
    def test_western_digits_with_currency_rejected(self):
        r = critic.check("احجز ربعك الآن بـ 3100 جنيه شامل التجهيز")
        self.assertTrue(any(h["code"] == "B13" for h in r["hard"]))

    def test_arabic_indic_price_rejected(self):
        r = critic.check("الربع بـ٣١٠٠ ج فقط")
        self.assertTrue(any(h["code"] == "B13" for h in r["hard"]))

    def test_plain_numbers_without_currency_allowed(self):
        r = critic.check("الخروف 50 كجم على الميزان و7 أسئلة قبل الاستثمار")
        self.assertFalse(any(h["code"] == "B13" for h in r["hard"]))

    def test_currencyless_context_words_allowed(self):
        r = critic.check("اطلب 4 جرعات رعاية مع المتابعة")
        self.assertFalse(any(h["code"] == "B13" for h in r["hard"]))

    def test_historical_price_records_kept_not_deleted(self):
        # سجل تاريخي داخلي يبقى موجودًا وموسومًا كتاريخي — القاعدة تمنع العرض لا الأرشيف
        readme = os.path.join(MARKETING, "02-التسويق", "حملات", "README.md")
        with open(readme, encoding="utf-8") as f:
            s = f.read()
        self.assertIn("٣١٠٠", s)          # السجل التاريخي محفوظ
        self.assertIn("B13", s)           # موسوم بقرار المنع

    def test_logo_rule_keeps_original_b12_id(self):
        comp = os.path.join(MARKETING, "04-الإنتاج", "terranex-ops", "context", "compliance.md")
        with open(comp, encoding="utf-8") as f:
            s = f.read()
        self.assertIn("**B12** | **الشعار يُعرض كبيرًا", s.replace("(", "("))  # B12 شعار سليم
        self.assertIn("| B13 |", s)  # معرف مستقل للأسعار


if __name__ == "__main__":
    unittest.main()
