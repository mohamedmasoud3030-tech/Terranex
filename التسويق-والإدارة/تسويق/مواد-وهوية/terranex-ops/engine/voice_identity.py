"""One narration allowlist shared by all marketing render entry points.

This validates declared identity, asset integrity and review metadata, not speaker
biometrics. It never generates, clones, or guesses a replacement voice.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from safe_paths import confine

PERSONAS = Path(__file__).resolve().parent.parent / "context" / "personas.json"
APPROVED_IDS = frozenset({"voice-00", "owner-eng-abdallah"})
APPROVED_ALTERNATIVE_IDS = frozenset({"Charon"})
AUDIO_ROOT = Path(__file__).resolve().parents[3]


def voice_bank():
    bank = json.loads(PERSONAS.read_text(encoding="utf-8"))["voice_bank"]
    ids = bank.get("allowed_voice_ids", [])
    if len(ids) != 2 or set(ids) != APPROVED_IDS:
        raise ValueError("بنك الأصوات يجب أن يحتوي الصوتين المعتمدين فقط")
    if (bank.get("default_voice_id") != "voice-00"
            or bank["default_narrator"].get("id") != "voice-00"
            or bank["default_narrator"].get("voice_id") != "voice-00"
            or bank["owner_voice"].get("id") != "owner-eng-abdallah"
            or bank["owner_voice"].get("voice_id") != "owner-eng-abdallah"
            or bank.get("allow_fallback") is not False):
        raise ValueError("هوية الصوت الافتراضي أو منع البدائل غير صحيح")
    alternatives = set(bank.get("alternative_voice_ids", []))
    if alternatives != APPROVED_ALTERNATIVE_IDS:
        raise ValueError("قائمة الأصوات البديلة غير صحيحة")
    return bank


def require_profile(voice_id):
    bank = voice_bank()
    if not isinstance(voice_id, str) or voice_id not in APPROVED_IDS | APPROVED_ALTERNATIVE_IDS:
        raise ValueError("صوت غير معتمد: voice-00 أو owner-eng-abdallah أو البديل المصرح Charon فقط")
    if voice_id == "voice-00":
        return bank["default_narrator"]
    if voice_id == "owner-eng-abdallah":
        return bank["owner_voice"]
    return bank["alternative_voices"][voice_id]


def require_narration(metadata, audio_path):
    if not isinstance(metadata, dict):
        raise ValueError("يلزم بيان هوية الصوت ومراجعة نصه قبل إرفاقه")
    voice_id = metadata.get("voice_id") or metadata.get("profile_id") or metadata.get("id")
    profile = require_profile(voice_id)
    # Reject conflicting ID fields instead of letting priority hide a third voice.
    if any(metadata[k] != voice_id for k in ("voice_id", "profile_id", "id") if k in metadata):
        raise ValueError("معرفات الصوت متعارضة")
    if voice_id == "owner-eng-abdallah":
        # No verified original/model or written consent has been recovered. A
        # caller-provided boolean/note must never unlock a real person's voice.
        raise ValueError("صوت عبدالله غير متاح: الأصل الخاص والموافقة الكتابية لم يتم التحقق منهما")
    if voice_id == "Charon" and (
            metadata.get("campaign_id") != "AD08"
            or metadata.get("scope") != "AD08 internal preview only"):
        raise ValueError("صوت Charon محصور في المعاينة الداخلية لـAD08")
    if (not isinstance(metadata.get("approval_note"), str)
            or not metadata["approval_note"].strip()):
        raise ValueError("يلزم إذن استخدام موثق للتعليق")
    audio = confine(str(audio_path), str(AUDIO_ROOT))
    digest = hashlib.sha256(Path(audio).read_bytes()).hexdigest()
    if metadata.get("sha256") != digest:
        raise ValueError("بصمة ملف التعليق لا تطابق الملف المعتمد")
    reference = profile.get("reference_asset", {})
    if digest == reference.get("sha256"):
        # The later explicit owner instruction permits this exact recording,
        # not fresh words from an unknown generator or a similar voice.
        reuse = reference.get("reuse_authorization", {})
        transcript = metadata.get("transcript")
        if (reuse.get("status") != "approved-existing-recording"
                or reuse.get("scope") != "unchanged-spoken-words-only"
                or metadata.get("historical_reuse") is not True
                or metadata.get("transcript_verification") != "historical-script"
                or not isinstance(transcript, list)
                or not transcript
                or transcript != reference.get("transcript")):
            raise ValueError("vo-09b تاريخي؛ إعادة استخدامه تتطلب تفويض المالك ونفس كلماته الأصلية")
    elif metadata.get("transcript_verification") != "human-reviewed":
        raise ValueError("يلزم تفريغ بشري مطابق للنص الجديد")
    return voice_id


def require_sidecar(audio_path):
    audio = confine(str(audio_path), str(AUDIO_ROOT))
    sidecar = Path(confine(audio + ".voice.json", str(AUDIO_ROOT)))
    if not sidecar.is_file():
        raise ValueError("يلزم ملف .voice.json بجوار التعليق يثبت هويته ومراجعة نصه")
    return require_narration(json.loads(sidecar.read_text(encoding="utf-8")), audio)
