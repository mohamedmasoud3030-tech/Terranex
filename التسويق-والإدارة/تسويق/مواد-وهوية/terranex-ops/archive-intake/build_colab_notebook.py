#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يبني Notebook واحدًا قابلًا للتشغيل في Google Colab المجاني لتقسيم الأرشيف سحابيًا.

التشغيل:  python build_colab_notebook.py
الناتج:   TerraNex-Split-Archive.ipynb  (بالقرب من هذا الملف)
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
OUT = os.path.join(REPO, "colab", "TerraNex-Split-Archive.ipynb")

cells = []


def md(text):
    cells.append({"cell_type": "markdown", "metadata": {}, "source": text.splitlines(keepends=True)})


def code(text):
    cells.append({"cell_type": "code", "execution_count": None, "metadata": {},
                  "outputs": [], "source": text.splitlines(keepends=True)})


md("""# تقسيم `Archive.zip` سحابيًا إلى 3 أجزاء — TerraNex

**كل شيء يحدث داخل Google Colab + Google Drive. لا ينزل شيء على جهازك.**

### ماذا يفعل هذا Notebook
1. يربط حساب Google Drive الخاص بك (بموافقتك في نافذة جوجل).
2. يتحقق أن `Archive.zip` هو الملف الصحيح (الحجم + بصمة SHA‑256).
3. ينشئ مجلدًا جديدًا **`TerraNex-Archive-Parts`** بجانب الأرشيف.
4. يقرأ الأرشيف على **3 نطاقات بايت** ويرفع كل نطاق كملف مستقل (~57.6 MiB).
5. يتحقق من حجم وبصمة كل جزء بعد رفعه.
6. يكتب **`manifest.json`** بالأسماء والأحجام والبصمات والترتيب ونطاقات البايت.

### ضمانات
- **لا يعدّل ولا يحذف الأرشيف الأصلي** — يقرأه فقط.
- كل جزء يُرفع ويُتحقق منه مستقلًا؛ **لو انقطع التنفيذ أعد التشغيل وسيكمل** من حيث وقف.
- لو اختلفت البصمة الكلية يتوقف ويكتب `status: hash-mismatch` ولا يعلن النجاح.

### التشغيل
`Runtime ← Run all` ثم وافق على ربط الحساب عندما يطلب. المدة المتوقعة: **3–8 دقائق**.
""")

code('''#@title ١) الإعدادات — لا تحتاج تغييرها { display-mode: "form" }
FILE_ID          = "1oUCCJhnWhtklCk_mJKYofNcGNuXRiPm8"   #@param {type:"string"}
EXPECTED_SIZE    = 181196089                              #@param {type:"integer"}
EXPECTED_SHA256  = "7a2bd417bb12b1d0eba348509b889d5f6a3f0d1af72d17734c943d3d7feed4d2"  #@param {type:"string"}
PARTS            = 3                                      #@param {type:"integer"}
FOLDER_NAME      = "TerraNex-Archive-Parts"               #@param {type:"string"}
CHUNK            = 8 * 1024 * 1024                        # 8 MiB لكل دفعة قراءة
TOOL_VERSION     = "1.0"

assert 1 < PARTS <= 10, "عدد الأجزاء يجب أن يكون بين 2 و10"
print("الإعدادات جاهزة.")
print("حجم الجزء التقريبي:", round(EXPECTED_SIZE / PARTS / 1048576, 2), "MiB")''')

code('''#@title ٢) ربط Google Drive بموافقتك
from google.colab import auth
import google.auth
from google.auth.transport.requests import AuthorizedSession
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload
import io, os, json, hashlib, time, datetime

auth.authenticate_user()
creds, project = google.auth.default(
    scopes=["https://www.googleapis.com/auth/drive"])
drive = build("drive", "v3", credentials=creds, cache_discovery=False)
session = AuthorizedSession(creds)
about = drive.about().get(fields="user(displayName,emailAddress)").execute()
print("تم الربط بحساب:", about["user"].get("emailAddress"))''')

code('''#@title ٣) التحقق من الأرشيف الأصلي قبل أي عمل
meta = drive.files().get(
    fileId=FILE_ID,
    fields="id,name,mimeType,size,md5Checksum,sha256Checksum,parents,modifiedTime,capabilities(canDownload)",
    supportsAllDrives=True).execute()

print("الاسم:", meta["name"])
print("الحجم:", meta["size"], "بايت")
print("SHA-256 من Drive:", meta.get("sha256Checksum"))

problems = []
if int(meta["size"]) != EXPECTED_SIZE:
    problems.append(f"الحجم مختلف: {meta['size']} بدل {EXPECTED_SIZE}")
if (meta.get("sha256Checksum") or "").lower() != EXPECTED_SHA256.lower():
    problems.append("بصمة SHA-256 مختلفة عن المتوقعة")
if not meta.get("capabilities", {}).get("canDownload", True):
    problems.append("الحساب لا يملك صلاحية تنزيل هذا الملف")
if problems:
    raise SystemExit("توقّف آمن — " + " | ".join(problems))

PARENT = meta["parents"][0]
ORIGINAL_MODIFIED = meta["modifiedTime"]
print("الأرشيف مطابق تمامًا. سنقرأه فقط ولن نعدّله.")''')

code('''#@title ٤) إنشاء مجلد الأجزاء (لا ينشئ نسخة مكررة لو موجود)
q = ("name = '%s' and mimeType = 'application/vnd.google-apps.folder' "
     "and '%s' in parents and trashed = false") % (FOLDER_NAME, PARENT)
found = drive.files().list(q=q, fields="files(id,name)", pageSize=10,
                           supportsAllDrives=True, includeItemsFromAllDrives=True).execute()["files"]
if found:
    FOLDER_ID = found[0]["id"]
    print("المجلد موجود مسبقًا:", FOLDER_ID)
else:
    folder = drive.files().create(
        body={"name": FOLDER_NAME, "mimeType": "application/vnd.google-apps.folder",
              "parents": [PARENT],
              "description": "أجزاء قراءة فقط من Archive.zip — أنشأها TerraNex Colab splitter"},
        fields="id,name").execute()
    FOLDER_ID = folder["id"]
    print("تم إنشاء المجلد:", FOLDER_ID)

existing = {f["name"]: f for f in drive.files().list(
    q="'%s' in parents and trashed = false" % FOLDER_ID,
    fields="files(id,name,size,md5Checksum)", pageSize=100,
    supportsAllDrives=True, includeItemsFromAllDrives=True).execute()["files"]}
print("ملفات موجودة داخل المجلد:", list(existing) or "لا شيء")''')

code('''#@title ٥) التقسيم والرفع والتحقق — قابل للاستكمال بعد أي انقطاع
BASE_URL = "https://www.googleapis.com/drive/v3/files/%s?alt=media&supportsAllDrives=true" % FILE_ID
bounds, step = [], EXPECTED_SIZE // PARTS
for i in range(PARTS):
    start = i * step
    end = (EXPECTED_SIZE - 1) if i == PARTS - 1 else (start + step - 1)
    bounds.append((i + 1, start, end))

overall = hashlib.sha256()
total_read = 0
parts_report = []


def read_range(start, end):
    """يقرأ نطاق بايت محدد ويتحقق من عدد البايتات المستلمة فعلًا."""
    want = end - start + 1
    r = session.get(BASE_URL, headers={"Range": f"bytes={start}-{end}"}, stream=True, timeout=300)
    if r.status_code == 206:
        cr = r.headers.get("Content-Range", "")
        expected_cr = f"bytes {start}-{end}/{EXPECTED_SIZE}"
        if cr != expected_cr:
            r.close()
            raise RuntimeError(f"Content-Range غير مطابق: {cr} بدل {expected_cr}")
        print("  نطاق مؤكد:", cr)
    elif r.status_code == 200:
        print("  تحذير: الخادم تجاهل Range وأرسل الملف كاملًا — سيتم قصّ النطاق محليًا بدقة.")
    else:
        raise RuntimeError(f"فشل التنزيل الجزئي: HTTP {r.status_code} {r.text[:200]}")

    buf = io.BytesIO()
    got = 0
    skipped = 0
    for chunk in r.iter_content(chunk_size=CHUNK):
        if not chunk:
            continue
        if r.status_code == 200:
            abs_start = skipped
            abs_end = skipped + len(chunk) - 1
            skipped += len(chunk)
            lo, hi = max(start, abs_start), min(end, abs_end)
            if lo > hi:
                if abs_start > end:
                    break
                continue
            chunk = chunk[lo - abs_start: hi - abs_start + 1]
        buf.write(chunk)
        got += len(chunk)
        if got > want:
            r.close()
            raise RuntimeError(f"استلمنا {got} بايت أكثر من المطلوب {want}")
    r.close()
    if got != want:
        raise RuntimeError(f"نقص بايتات: استلمنا {got} من {want} للنطاق {start}-{end}")
    buf.seek(0)
    return buf


for order, start, end in bounds:
    name = f"Archive.part{order:02d}-of-{PARTS:02d}.bin"
    want = end - start + 1
    print(f"\\n=== الجزء {order}/{PARTS}: {name}  [{start}..{end}] = {want} بايت ===")
    t0 = time.time()
    buf = read_range(start, end)
    data = buf.getvalue()
    assert len(data) == want
    part_sha = hashlib.sha256(data).hexdigest()
    part_md5 = hashlib.md5(data).hexdigest()
    overall.update(data)
    total_read += len(data)

    prev = existing.get(name)
    if prev and int(prev.get("size", -1)) == want and prev.get("md5Checksum") == part_md5:
        print("  موجود مسبقًا ومطابق — تخطّي الرفع (استكمال).")
        fid = prev["id"]
    else:
        if prev:
            print("  نسخة قديمة غير مطابقة — سيُحدَّث محتواها.")
            up = drive.files().update(
                fileId=prev["id"],
                media_body=MediaIoBaseUpload(io.BytesIO(data), mimetype="application/octet-stream",
                                             resumable=True, chunksize=8 * 1024 * 1024),
                fields="id,name,size,md5Checksum", supportsAllDrives=True).execute()
        else:
            up = drive.files().create(
                body={"name": name, "parents": [FOLDER_ID],
                      "description": f"جزء {order} من {PARTS} — بايتات {start}..{end} من Archive.zip (قراءة فقط)"},
                media_body=MediaIoBaseUpload(io.BytesIO(data), mimetype="application/octet-stream",
                                             resumable=True, chunksize=8 * 1024 * 1024),
                fields="id,name,size,md5Checksum", supportsAllDrives=True).execute()
        fid = up["id"]
        if int(up["size"]) != want or up.get("md5Checksum") != part_md5:
            raise RuntimeError(f"التحقق بعد الرفع فشل للجزء {order}: size={up['size']} md5={up.get('md5Checksum')}")
        print("  رُفع وتُم التحقق منه على Drive ✔")

    parts_report.append({
        "order": order, "name": name, "drive_file_id": fid,
        "byte_range": {"start": start, "end": end}, "size": want,
        "sha256": part_sha, "md5": part_md5,
        "web_link": f"https://drive.google.com/file/d/{fid}/view",
    })
    del data, buf
    print(f"  انتهى في {time.time() - t0:.1f} ثانية")

print("\\n مجموع البايتات المقروءة:", total_read)''')

code('''#@title ٦) مطابقة البصمة الكلية وكتابة manifest.json
computed = overall.hexdigest()
print("SHA-256 المحسوب من البايتات:", computed)
print("SHA-256 المتوقع             :", EXPECTED_SHA256)

ok = (computed.lower() == EXPECTED_SHA256.lower()) and (total_read == EXPECTED_SIZE)
status = "complete-verified" if ok else "hash-mismatch-DO-NOT-EXTRACT"

after = drive.files().get(fileId=FILE_ID, fields="size,sha256Checksum,modifiedTime",
                          supportsAllDrives=True).execute()
original_untouched = (after["modifiedTime"] == ORIGINAL_MODIFIED
                      and int(after["size"]) == EXPECTED_SIZE
                      and (after.get("sha256Checksum") or "").lower() == EXPECTED_SHA256.lower())

manifest = {
    "tool": "TerraNex Colab cloud splitter", "tool_version": TOOL_VERSION,
    "created_at_utc": datetime.datetime.utcnow().isoformat() + "Z",
    "status": status,
    "original": {"file_id": FILE_ID, "name": meta["name"], "size": EXPECTED_SIZE,
                 "sha256": EXPECTED_SHA256, "md5": meta.get("md5Checksum"),
                 "modified_time": ORIGINAL_MODIFIED, "untouched_verified": original_untouched},
    "folder": {"name": FOLDER_NAME, "id": FOLDER_ID},
    "part_count": PARTS,
    "parts": parts_report,
    "reassembly": {
        "order": [p["name"] for p in parts_report],
        "method": "concatenate bytes in ascending order",
        "expected_total_bytes": EXPECTED_SIZE,
        "expected_sha256": EXPECTED_SHA256,
        "rule": "لا تبدأ الاستخراج إلا إذا طابق SHA-256 بعد التجميع",
    },
    "safety": ["الأرشيف الأصلي للقراءة فقط", "لم يُحذف أو يُعدّل أي ملف موجود",
               "كل جزء تُحقق من حجمه وبصمته بعد الرفع",
               "إعادة التشغيل تتخطى الأجزاء الصحيحة الموجودة"],
}
blob = json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8")

mf = existing.get("manifest.json")
if mf:
    drive.files().update(fileId=mf["id"],
                         media_body=MediaIoBaseUpload(io.BytesIO(blob), mimetype="application/json"),
                         fields="id", supportsAllDrives=True).execute()
else:
    drive.files().create(body={"name": "manifest.json", "parents": [FOLDER_ID]},
                         media_body=MediaIoBaseUpload(io.BytesIO(blob), mimetype="application/json"),
                         fields="id", supportsAllDrives=True).execute()

print("\\nالحالة:", status)
print("الأرشيف الأصلي لم يُمس:", original_untouched)
if not ok:
    raise SystemExit("توقّف: البصمة غير مطابقة — لا تستخدم الأجزاء ولا تستخرج شيئًا.")
if not original_untouched:
    raise SystemExit("تحذير: تغيّر الأرشيف الأصلي أثناء العمل — أعد التشغيل من البداية.")''')

code('''#@title ٧) الملخص النهائي — أبلغ Arena أن الأجزاء جاهزة
from IPython.display import display, HTML
rows = "".join(
    f"<tr><td>{p['order']}</td><td>{p['name']}</td><td>{p['size']:,}</td>"
    f"<td>{p['byte_range']['start']}–{p['byte_range']['end']}</td>"
    f"<td><code>{p['sha256'][:16]}…</code></td>"
    f"<td><a href='{p['web_link']}' target='_blank'>فتح</a></td></tr>"
    for p in parts_report)
display(HTML(f"""
<h3>تم — {len(parts_report)} أجزاء داخل {FOLDER_NAME}</h3>
<table border=1 cellpadding=6 style='border-collapse:collapse'>
<tr><th>#</th><th>الاسم</th><th>بايت</th><th>النطاق</th><th>SHA-256</th><th>رابط</th></tr>{rows}</table>
<p><b>الأرشيف الأصلي:</b> لم يُعدّل ولم يُحذف.<br>
<b>البصمة الكلية:</b> مطابقة ✔<br>
<b>الخطوة التالية:</b> اكتب في محادثة Arena: «الأجزاء جاهزة في TerraNex-Archive-Parts».</p>
"""))
print("معرّف المجلد:", FOLDER_ID)''')

md("""---
## لو انقطع التنفيذ
أعد `Runtime ← Run all`. سيتعرّف على الأجزاء الصحيحة الموجودة ويتخطّى رفعها، ويعيد التحقق من البصمة الكلية.

## لو ظهر `hash-mismatch`
لا تستخدم الأجزاء. هذا يعني أن الأرشيف تغيّر أو أن القراءة نقصت. شغّل Notebook مرة أخرى؛ ولو تكرر، أبلغ Arena بالرسالة كما هي.

## ماذا يحدث بعد ذلك في Arena
1. تنزيل الأجزاء الثلاثة (كلٌّ أقل من 100 MiB) عبر موصّل Drive.
2. تجميعها بالترتيب ومطابقة `SHA-256 = 7a2bd417…`.
3. فحص سلامة ZIP قبل الاستخراج، ثم فكّه في مساحة عمل معزولة.
4. الجرد والتحليل البصري وأوراق المعاينة وتقييم الجودة والخصوصية.
5. **لا دمج في المكتبة الإنتاجية ولا نشر ولا دمج PR قبل مراجعتك.**
""")

nb = {
    "cells": cells,
    "metadata": {
        "colab": {"name": "TerraNex-Split-Archive.ipynb", "provenance": [], "toc_visible": True},
        "kernelspec": {"display_name": "Python 3", "name": "python3"},
        "language_info": {"name": "python"},
    },
    "nbformat": 4,
    "nbformat_minor": 0,
}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(nb, f, ensure_ascii=False, indent=1)
    f.write("\n")
print("notebook:", OUT)
print("cells:", len(cells), "| code cells:", sum(1 for c in cells if c["cell_type"] == "code"))
