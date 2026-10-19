#!/usr/bin/env bash
# TerraNex Ops — تثبيت التبعيات بأمر واحد (آمن ومنّكّر: pip --user فقط).
# الاستخدام:  bash setup.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> تثبيت تبعيات بايثون (pillow / numpy / imageio-ffmpeg / uharfbuzz / python-bidi / freetype-py)"
if python3 -m pip install --user -r requirements.txt 2>/dev/null; then
    :
else
    # ديبيان 12+ (PEP 668): بيئة مُدارة — نستخدم الفلاغ الرسمي بمسؤولية على مستوى المستخدم فقط
    python3 -m pip install --user --break-system-packages -r requirements.txt
fi

echo "==> فحص ذاتي بعد التثبيت"
python3 engine/selfcheck.py
echo "==> تم. المحرك جاهز للعمل."
