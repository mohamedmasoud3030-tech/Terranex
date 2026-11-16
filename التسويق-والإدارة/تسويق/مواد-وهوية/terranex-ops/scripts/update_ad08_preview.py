import json
from pathlib import Path

p = Path('output/creative-projects/phase3-improvement-specs/AD08-S3-local-product-service-v001.json')
d = json.loads(p.read_text(encoding='utf-8'))
NL = '\n'
base = 'preview-media/'
clips = [
    {'id': 'S01', 'asset_id': 'gh-a28', 'path': base+'gh-a28.mp4', 'start': 2.0, 'end': 6.6, 'source_start': 2.0, 'source_end': 6.6, 'crop': {}, 'sharpen': False},
    {'id': 'S02', 'asset_id': 'gh-a43', 'path': base+'gh-a43.mp4', 'start': 24.5, 'end': 28.18, 'source_start': 24.5, 'source_end': 28.18, 'crop': {}, 'sharpen': False},
    {'id': 'S03', 'asset_id': 'gh-a31', 'path': base+'gh-a31.mp4', 'start': 0.0, 'end': 2.66, 'source_start': 0.0, 'source_end': 2.66, 'crop': {}, 'sharpen': False},
    {'id': 'S04', 'asset_id': 'gh-a38', 'path': base+'gh-a38.mp4', 'start': 10.0, 'end': 13.12, 'source_start': 10.0, 'source_end': 13.12, 'crop': {}, 'sharpen': False},
    {'id': 'S05', 'asset_id': 'gh-a35', 'path': base+'gh-a35.mp4', 'start': 8.5, 'end': 10.84, 'source_start': 8.5, 'source_end': 10.84, 'crop': {}, 'sharpen': False},
    {'id': 'S06', 'asset_id': 'gh-a17', 'path': base+'gh-a17.mp4', 'start': 2.0, 'end': 5.64, 'source_start': 2.0, 'source_end': 5.64, 'crop': {}, 'sharpen': False},
]
hook = 'لأهل إسكندرية… فتحنا باب الحجز على الربع البرقي من TerraNex!'
d['hook'], d['hook_sec'], d['clips'], d['endcard_sec'] = hook, 4.6, clips, 0.0
d['captions'] = [
    {'from': 0.0, 'to': 4.6, 'text': 'لأهل إسكندرية…'+NL+'فتحنا باب الحجز على الربع البرقي من TerraNex!'},
    {'from': 4.6, 'to': 8.28, 'text': 'خليك شايف الحيوان قدامك، مش مجرد كلام.'},
    {'from': 8.28, 'to': 10.94, 'text': 'والوزن بيتعمل قدامك على الميزان.'},
    {'from': 10.94, 'to': 14.06, 'text': 'واللي بنفحصه قدامك يتقال زي ما هو.'},
    {'from': 14.06, 'to': 16.4, 'text': 'تشوف التعامل خطوة بخطوة.'},
    {'from': 16.4, 'to': 20.04, 'text': 'للتفاصيل الحالية قبل الحجز:'+NL+'واتساب فقط 01010154221'},
]
d['endcard'] = {'headline': '', 'subtitle': '', 'cta': '', 'disclosure': ''}
d['audio'] = {'ambient_from': 0, 'original_gain': 0.20, 'status': 'voice_blocked_pending_project_voice-00_source'}
d['storyboard'] = [
    {'edit_range': '0.0-4.6', 'function': 'real_hook', 'source': 'gh-a28.mp4', 'source_range': '2.00-6.60', 'visual': 'رأس حقيقي منفرد في فناء المزرعة.', 'on_screen_copy': 'لأهل إسكندرية…'+NL+'فتحنا باب الحجز على الربع البرقي من TerraNex!', 'voice_line': hook, 'evidence_boundary': 'ذكر المدينة استثناء B9 موثق لـAD08 فقط؛ لا يثبت تغطية الأحياء أو مواعيد التوصيل.'},
    {'edit_range': '4.6-8.28', 'function': 'animal_context', 'source': 'gh-a43.mp4', 'source_range': '24.50-28.18', 'visual': 'حيوانات حقيقية داخل الحظيرة.', 'on_screen_copy': 'خليك شايف الحيوان قدامك، مش مجرد كلام.', 'voice_line': 'خليك شايف الحيوان قدامك، مش مجرد كلام.', 'evidence_boundary': 'لا يثبت العدد أو التوفر الحالي.'},
    {'edit_range': '8.28-10.94', 'function': 'weighing_action', 'source': 'gh-a31.mp4', 'source_range': '0.00-2.66', 'visual': 'الحيوان يُقاد باتجاه الميزان الأصفر.', 'on_screen_copy': 'والوزن بيتعمل قدامك على الميزان.', 'voice_line': 'والوزن بيتعمل قدامك على الميزان.', 'evidence_boundary': 'يثبت فعل الوزن فقط؛ لا يظهر رقم وزن.'},
    {'edit_range': '10.94-14.06', 'function': 'inspection_detail', 'source': 'gh-a38.mp4', 'source_range': '10.00-13.12', 'visual': 'تفصيل الفحص الظاهر في الفم/الأسنان.', 'on_screen_copy': 'واللي بنفحصه قدامك يتقال زي ما هو.', 'voice_line': 'واللي بنفحصه قدامك يتقال زي ما هو.', 'evidence_boundary': 'لا يوصف ككشف بيطري أو إثبات عمر/صحة.'},
    {'edit_range': '14.06-16.40', 'function': 'handling', 'source': 'gh-a35.mp4', 'source_range': '8.50-10.84', 'visual': 'تعامل حقيقي مع الحيوان.', 'on_screen_copy': 'تشوف التعامل خطوة بخطوة.', 'voice_line': 'تشوف التعامل خطوة بخطوة.', 'evidence_boundary': 'لا يثبت اكتمال التجهيز أو الجودة الصحية.'},
    {'edit_range': '16.40-20.04', 'function': 'single_cta_over_real_footage', 'source': 'gh-a17.mp4', 'source_range': '2.00-5.64', 'visual': 'ختام عند المعلف مع CTA فوق اللقطة الحقيقية.', 'on_screen_copy': 'للتفاصيل الحالية قبل الحجز:'+NL+'واتساب فقط 01010154221', 'voice_line': 'للتفاصيل الحالية قبل الحجز، ابعتلنا على واتساب.', 'evidence_boundary': 'لا سعر أو حساب أو ادعاء تغطية أو موعد توصيل.'},
]
d['script']['text'] = hook+NL+'خليك شايف الحيوان قدامك، مش مجرد كلام.'+NL+'والوزن بيتعمل قدامك على الميزان.'+NL+'واللي بنفحصه قدامك يتقال زي ما هو.'+NL+'تشوف التعامل خطوة بخطوة. للتفاصيل الحالية قبل الحجز، ابعتلنا على واتساب.'
d['script']['status'] = 'owner-city-mention-approved-script-ready-voice-00-recording-pending'
d['script']['evidence_linked'] = True
d['script']['voice_turns'] = [
    {'text': hook, 'style': 'clear, warm and confident'},
    {'text': 'خليك شايف الحيوان قدامك، مش مجرد كلام.', 'style': 'natural Egyptian conversational'},
    {'text': 'والوزن بيتعمل قدامك على الميزان. واللي بنفحصه قدامك يتقال زي ما هو.', 'style': 'calm and precise'},
    {'text': 'تشوف التعامل خطوة بخطوة. للتفاصيل الحالية قبل الحجز، ابعتلنا على واتساب.', 'style': 'warm, single clear CTA'},
]
d['caption'] = {'text': hook+NL+'شوف الحيوان والوزن والفحص قدامك، من غير كلام عام أو حسابات بلا دليل.'+NL+'للتفاصيل الحالية قبل الحجز: واتساب فقط 01010154221'+NL+'#TerraNex #ضاني_برقي #حجز_لحوم', 'cta_count': 1, 'price_free': True, 'delivery_claim_free': True}
d['source_asset_policy'].update({'source_review_required': False, 'source_review_approved': True, 'scene_import_approved': True, 'source_review_note': 'تمت مراجعة الإطارات الفعلية من كائنات Git التاريخية؛ gh-a38 صالح لنافذة الفحص 10.00–14.00 فقط.', 'source_restore_records': {'gh-a28': {'sha256': '3c3ce3cd9f92c567acc3fd35a3743ed78a0f282d1bc1c68984f06d3bac650951', 'git_blob': '4014a48c7b7a66f356ff9d927d7024abb7e846bc'}, 'gh-a43': {'sha256': '3025ab60078a35d619d98fd77e71314cf8a902f63cf7e12aa1339efdab5d698e', 'git_blob': '1dd6ac36831a32b3b52a1c6c4f5d78c5b6c93a6b'}, 'gh-a17': {'sha256': 'dbafbdd9ba803761bf9cc3db3a61ccf1280943493bbd685a26cde5a87efaf769', 'git_blob': '72207a2684f707565838b6f785cc7aa5fbe3069f'}, 'gh-a31': {'sha256': '777485a762c25a7046a7533a1c7a8a481e30b367c27455499c7bbccca2b351e1', 'git_blob': '635a0097996ac1ff6464c94e4d955997382ded94'}, 'gh-a35': {'sha256': 'fcc9d518cfc24e28e9642f3dedd5621c722c20da9f2efd118185db71ebbd7afb', 'git_blob': '66a154eaf433f858f64b06e0f5aa843a98690104'}, 'gh-a38': {'sha256': '8ec0164bfd547e671869ed4693eeb863cc2356012f07e1c809b0d54b2d1f3f29', 'git_blob': 'dcd915a24bf45ebf1bb59eac2055833daa783a09'}}})
d['approval'].update({'preview_approved_internal': True, 'preview_scope': 'internal_only', 'preview_rendered_with_audio': False, 'preview_status': 'visual_preview_authorized_voice_pending', 'source_review_approved': True, 'render_approved': False, 'recording_approved': False, 'owner_publish_approval': 'pending', 'publication_ready': False})
d['preview_approved_internal'] = True
d['preview_scope'] = 'internal_only'
d['render_approved'] = False
d['preview_gate'] = {'approved': True, 'scope': 'internal_only', 'limits': ['AD08 only', 'no publication', 'no merge', 'no final render approval', 'no audio claim until voice-00 sidecar and human transcript exist'], 'blocked_by': ['voice-00 recording source is not callable in this environment']}
d['qa_gates'] = ['كل لقطة من مادة الشركة الحقيقية ومراجعة المصدر قبل الاستيراد', 'لا شاشات كتابة فقط: CTA فوق لقطة حقيقية، والختام النصي المنفصل ملغى', 'لا لقطة مكررة؛ gh-a38 للفحص فقط 10.00–14.00', 'critic يمر بلا B1/B2/B4/B5/B6/B7/B8/B9/B10/B11/B12', 'لا سعر أو عملية حسابية أو ادعاء توصيل', 'CTA واحد فقط بالرقم 01010154221', 'voice-00 مطلوب بتسجيل جديد؛ لا يُعاد استخدام تسجيل قديم لكلمات جديدة', 'فحص التزامن والصمت والصوت بعد توفر تسجيل voice-00 الموثق', 'المعاينة الداخلية فقط؛ لا نشر ولا دمج ولا اعتماد نسخة نهائية']
p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(p)
