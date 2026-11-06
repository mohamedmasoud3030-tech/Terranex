#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Local authenticated HTTP server for TerraNex production robot; no publishing routes."""
import hmac
import json
import os
import shutil
import tempfile
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs
import production_robot as B


class Api(BaseHTTPRequestHandler):
    def send(self, code, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def check(self):
        token = os.environ.get("TERRANEX_BOT_TOKEN", "")
        if len(token) < 24 or not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + token):
            self.send(401, {"error": "unauthorized"})
            return False
        return True

    def body(self):
        size = int(self.headers.get("Content-Length", "0"))
        if not 2 <= size <= 2 * 1024 * 1024:
            raise B.Blocked("JSON body size invalid")
        data = json.loads(self.rfile.read(size))
        if not isinstance(data, dict):
            raise B.Blocked("object required")
        return data

    def jobpath(self, ident):
        if not isinstance(ident, str) or not ident.isalnum() or len(ident) != 32:
            raise B.Blocked("invalid job id")
        return B.WORK/"jobs"/(ident+".json")

    def do_GET(self):
        if not self.check():
            return
        try:
            segments = urlparse(self.path).path.strip("/").split("/")
            if segments == ["v1", "health"]:
                return self.send(200, {"ok": True, "publication_enabled": False})
            if len(segments) >= 3 and segments[:2] == ["v1","jobs"]:
                job = json.loads(self.jobpath(segments[2]).read_text(encoding="utf-8"))
                if len(segments) == 3:
                    return self.send(200, job)
                if len(segments) == 4 and segments[3] == "video":
                    if job["status"] != "ready-for-review":
                        return self.send(404, {"error": "video not ready"})
                    video = B.confined(job["file"], B.WORK)
                    self.send_response(200)
                    self.send_header("Content-Type","video/mp4")
                    self.send_header("Content-Length", str(video.stat().st_size))
                    self.send_header("Cache-Control", "private, no-store")
                    self.end_headers()
                    with video.open("rb") as stream:
                        shutil.copyfileobj(stream, self.wfile, 1024*1024)
                    return
            self.send(404, {"error": "not found"})
        except (OSError, ValueError, KeyError, B.Blocked) as exc:
            self.send(400, {"error": str(exc)})

    def do_POST(self):
        if not self.check():
            return
        try:
            segments = urlparse(self.path).path.strip("/").split("/")
            body = self.body()
            if segments == ["v1", "jobs"]:
                planned = B.make_plan(body, B.assets())
                ident = uuid.uuid4().hex
                job = {"id": ident, "status": "planned" if planned["ready_for_render"] else "blocked",
                       "plan": planned, "published": False}
                B.write_json(self.jobpath(ident), job)
                return self.send(201, job)
            if len(segments) == 4 and segments[:2] == ["v1","assets"] and segments[3] == "review":
                if body.get("human_reviewed") is not True:
                    raise B.Blocked("explicit human review required")
                item = B.review_upload(segments[2], body.get("description", ""), body.get("duration"))
                return self.send(200, {"id": item["id"], "reviewed": True})
            if len(segments) == 4 and segments[:2] == ["v1","jobs"] and segments[3] == "render":
                jobfile = self.jobpath(segments[2])
                job = json.loads(jobfile.read_text(encoding="utf-8"))
                meta = body.get("voice_metadata")
                if not isinstance(meta, dict):
                    raise B.Blocked("approved voice metadata required")
                voice = B.confined(body["voice_path"], B.MARKETING)
                spec = B.make_spec(job["plan"], meta)
                B.verify_narration(voice, meta, job["plan"]["duration_seconds"])
                job["status"] = "rendering"
                B.write_json(jobfile, job)
                def worker():
                    try:
                        out = B.WORK/"videos"/(job["id"]+".mp4")
                        result = B.render(job["plan"], voice, meta, out)
                        job.update(result)
                    except Exception as e:
                        job.update({"status": "failed", "error": str(e)})
                    B.write_json(jobfile, job)
                threading.Thread(target=worker, daemon=True).start()
                return self.send(202, {"id": job["id"], "status": "rendering"})
            self.send(404, {"error": "not found"})
        except (OSError, ValueError, KeyError, B.Blocked) as exc:
            self.send(400, {"error": str(exc)})

    def do_PUT(self):
        if not self.check():
            return
        parsed = urlparse(self.path)
        if parsed.path != "/v1/assets":
            return self.send(404, {"error": "not found"})
        temp = None
        try:
            q = parse_qs(parsed.query)
            role = q.get("role", [""])[0]
            suffix = Path(q.get("filename", [""])[0]).suffix.lower()
            n = int(self.headers.get("Content-Length", "0"))
            if role not in B.ROLES or suffix not in B.EXTS or not 0 < n <= B.MAX_BYTES:
                raise B.Blocked("invalid upload role, type or size")
            B.WORK.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=B.WORK, suffix=suffix, delete=False) as stream:
                temp = Path(stream.name)
                while n:
                    chunk = self.rfile.read(min(n, 1024*1024))
                    if not chunk:
                        raise B.Blocked("truncated media upload")
                    stream.write(chunk)
                    n -= len(chunk)
            a = B.ingest(temp, role)
            self.send(201, {"asset_id": a["id"], "sha256": a["sha256"], "review_required": True})
        except (OSError, ValueError, B.Blocked) as exc:
            self.send(400, {"error": str(exc)})
        finally:
            if temp is not None:
                temp.unlink(missing_ok=True)


def serve(host="127.0.0.1", port=8765):
    if len(os.environ.get("TERRANEX_BOT_TOKEN", "")) < 24:
        raise B.Blocked("TERRANEX_BOT_TOKEN is required (24+ characters)")
    if host not in ("127.0.0.1", "localhost", "::1") and os.environ.get("TERRANEX_ALLOW_REMOTE") != "1":
        raise B.Blocked("public binding refused; use TLS reverse proxy")
    print("TerraNex robot API ready: " + str(host) + ":" + str(port), flush=True)
    ThreadingHTTPServer((host, port), Api).serve_forever()
