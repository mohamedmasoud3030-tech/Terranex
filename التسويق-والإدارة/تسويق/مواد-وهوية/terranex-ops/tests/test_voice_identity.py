"""Regression gates for all narration entry points; fixtures are not voice models."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ENGINE = Path(__file__).resolve().parents[1] / 'engine'
sys.path.insert(0, str(ENGINE))
import voice_identity as VI
import reel_build as R
import make_video as MV
import make_reel_from_footage as MR
import creative_director as CD


class VoiceIdentityTests(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory(dir=VI.AUDIO_ROOT)
        self.addCleanup(self.td.cleanup)
        self.asset = Path(self.td.name) / 'fixture.wav'
        self.asset.write_bytes(b'non-speaker-test-fixture')
        self.meta = {'voice_id': 'voice-00', 'sha256': hashlib.sha256(self.asset.read_bytes()).hexdigest(),
                     'approval_note': 'unit test only', 'transcript_verification': 'human-reviewed'}

    def test_bank_has_exactly_two_ids_and_default(self):
        b = VI.voice_bank()
        self.assertEqual(b['allowed_voice_ids'], ['voice-00', 'owner-eng-abdallah'])
        self.assertEqual(b['default_voice_id'], 'voice-00')

    def test_third_voice_rejected(self):
        for voice_id in ('voice-01', 'ar_JO-kareem', 'ar-eg-calm-confident', '', None):
            with self.subTest(voice_id=voice_id), self.assertRaises(ValueError):
                VI.require_profile(voice_id)

    def test_third_voice_in_configuration_rejected(self):
        data = json.loads(VI.PERSONAS.read_text())
        data['voice_bank']['allowed_voice_ids'].append('voice-99')
        p = Path(self.td.name) / 'personas.json'; p.write_text(json.dumps(data))
        with patch.object(VI, 'PERSONAS', p), self.assertRaises(ValueError):
            VI.voice_bank()

    def test_reviewed_asset_binding_passes(self):
        self.assertEqual(VI.require_narration(self.meta, self.asset), 'voice-00')

    def test_replaced_asset_rejected(self):
        self.asset.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'بصمة'):
            VI.require_narration(self.meta, self.asset)

    def test_conflicting_ids_rejected(self):
        self.meta['id'] = 'voice-99'
        with self.assertRaisesRegex(ValueError, 'متعارضة'):
            VI.require_narration(self.meta, self.asset)

    def test_owner_cannot_be_unlocked_by_note_or_boolean(self):
        self.meta.update(voice_id='owner-eng-abdallah', consent=True, approval_note='I approve')
        with self.assertRaisesRegex(ValueError, 'عبدالله'):
            VI.require_narration(self.meta, self.asset)

    def test_historical_words_cannot_be_reused_as_new_voice(self):
        profile = copy.deepcopy(VI.require_profile('voice-00'))
        profile['reference_asset']['sha256'] = self.meta['sha256']
        with patch.object(VI, 'require_profile', return_value=profile), self.assertRaisesRegex(ValueError, 'تاريخي'):
            VI.require_narration(self.meta, self.asset)

    def test_review_and_approval_required(self):
        for key in ('transcript_verification', 'approval_note', 'voice_id', 'sha256'):
            m = dict(self.meta); m.pop(key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                VI.require_narration(m, self.asset)

    def test_legacy_sidecar_is_required(self):
        with self.assertRaises(ValueError): VI.require_sidecar(self.asset)
        Path(str(self.asset)+'.voice.json').write_text(json.dumps(self.meta))
        self.assertEqual(VI.require_sidecar(self.asset), 'voice-00')

    def test_make_video_rejects_before_ffmpeg(self):
        with self.assertRaises(ValueError): MV.render({}, 'unused.mp4', str(self.asset))

    def test_legacy_reel_rejects_before_probe(self):
        with self.assertRaises(ValueError): MR.render('missing.mp4', [], 'unused.mp4', str(self.asset))

    def test_reel_build_rejects_before_reading_clips(self):
        p = Path(self.td.name)/'spec.json';p.write_text(json.dumps({'voice':{'voice_id':'voice-99'}}))
        with patch.object(R, 'MARKETING_ROOT', self.td.name), self.assertRaises(ValueError):
            R.build(str(p), str(self.asset), 'unused.mp4')

    def test_attach_voice_default_is_canonical(self):
        import inspect
        self.assertEqual(inspect.signature(CD.attach_voice).parameters['profile_id'].default, 'voice-00')

    def test_new_brief_uses_canonical_voice(self):
        self.assertEqual(CD.parse_brief('فيديو متابعة الحيوانات 20 ثانية بتعليق صوتي')["voice"]["profile_id"], 'voice-00')

    def test_exact_historical_recording_requires_explicit_reuse_and_same_words(self):
        profile = copy.deepcopy(VI.require_profile('voice-00'))
        profile['reference_asset']['sha256'] = self.meta['sha256']
        self.meta.update(historical_reuse=True, transcript_verification='historical-script',
                         transcript=profile['reference_asset']['transcript'])
        with patch.object(VI, 'require_profile', return_value=profile):
            self.assertEqual(VI.require_narration(self.meta, self.asset), 'voice-00')
            self.meta['transcript'] = ['different new words']
            with self.assertRaises(ValueError): VI.require_narration(self.meta, self.asset)

    def test_audio_outside_marketing_root_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            outside = Path(td) / 'outside.wav';outside.write_bytes(self.asset.read_bytes())
            with self.assertRaisesRegex(ValueError, 'outside allowed root'):
                VI.require_narration(self.meta, outside)
