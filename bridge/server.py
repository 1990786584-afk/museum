#!/usr/bin/env python3
"""Private, same-origin Shelf gallery for the Museum iOS app.

The iPhone authenticates with its Ephemera her token, then receives a short
HttpOnly Secure cookie. Only this authenticated gallery exposes private photos.
Bind to 127.0.0.1 and proxy under HTTPS /date/museum-gallery/.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hmac
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import os
from pathlib import Path
import secrets
import threading
import time
from urllib.parse import unquote, urlsplit

from sync import EphemeraClient, sync_gallery

PREFIX = "/museum-gallery"
SESSION_SECONDS = 3600

class State:
    def __init__(self, root: Path, token: str, api: EphemeraClient, shelf: Path, eph: Path):
        if not token:
            raise ValueError("Missing private bearer token")
        prefix = os.environ.get("MUSEUM_PUBLIC_PREFIX", PREFIX)
        if not prefix.startswith("/") or "//" in prefix or ".." in prefix or not prefix.endswith(PREFIX):
            raise ValueError("invalid public reverse-proxy prefix")
        self.cookie_path = prefix + "/"
        self.root = root.resolve()
        self.token = token.encode("utf-8")
        self.api = api
        self.shelf = shelf
        self.ephemera = eph
        self.sessions: dict[str, float] = {}
        self.lock = threading.Lock()
        self.sync_lock = threading.Lock()
        self.last_sync = 0.0
        self.last_result = {}
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.root, 0o700)

    def bearer_ok(self, header: str) -> bool:
        scheme, sep, token = header.partition(" ")
        return bool(sep) and scheme == "Bearer" and hmac.compare_digest(
            token.encode("utf-8"), self.token
        )

    def create_session(self):
        raw = secrets.token_urlsafe(32)
        with self.lock:
            # Keep the session map bounded.
            now = time.time()
            self.sessions = {key: exp for key, exp in self.sessions.items() if exp > now}
            self.sessions[raw] = now + SESSION_SECONDS
        return raw

    def cookie_ok(self, header: str) -> bool:
        cookie = SimpleCookie()
        try:
            cookie.load(header)
        except Exception:
            return False
        item = cookie.get("museum_sid")
        if item is None:
            return False
        key = item.value
        with self.lock:
            exp = self.sessions.get(key)
            return exp is not None and exp > time.time()

    def sync(self) -> dict:
        with self.sync_lock:
            result = sync_gallery(self.api, self.root, self.shelf, self.ephemera)
            self.last_sync = time.time()
            self.last_result = result
            return result


class Handler(BaseHTTPRequestHandler):
    server: "PrivateServer"

    def log_message(self, format, *args):
        # Do not log private path identifiers or tokens.
        return

    def headers_safe(self, size=0):
        self.send_header("Cache-Control", "private, no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self' data: blob:; img-src 'self' data: blob:; "
            "font-src 'self' data:; style-src 'self' 'unsafe-inline'; "
            "script-src 'self' 'unsafe-inline'; connect-src 'self'; "
            "frame-ancestors 'none'; base-uri 'self'; form-action 'none'",
        )
        self.send_header("Content-Length", str(size))

    def respond(self, status, content=b"", kind="application/json; charset=utf-8",
                cookie=None):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        if cookie is not None:
            self.send_header(
                "Set-Cookie",
                f"museum_sid={cookie}; Path={self.server.state.cookie_path}; Secure; HttpOnly; "
                "SameSite=Strict; Max-Age=3600",
            )
        self.headers_safe(len(content))
        self.end_headers()
        if content:
            self.wfile.write(content)

    def do_POST(self):
        path = urlsplit(self.path).path
        if path not in (PREFIX + "/session", PREFIX + "/sync"):
            self.respond(404, b'{"error":"not_found"}')
            return
        # Cross-site POST cannot obtain a new session without the bearer token.
        if not self.server.state.bearer_ok(self.headers.get("Authorization", "")):
            self.respond(401, b'{"error":"unauthorized"}')
            return
        if int(self.headers.get("Content-Length", "0") or 0) > 1024:
            self.respond(413, b'{"error":"too_large"}')
            return
        if path.endswith("/session"):
            self.respond(204, b"", cookie=self.server.state.create_session())
            return
        try:
            result = self.server.state.sync()
        except Exception:
            # Never leak token, local directory structure, or private date details.
            self.respond(502, b'{"error":"sync_unavailable"}')
            return
        self.respond(200, json.dumps(result).encode("utf-8"))

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == PREFIX + "/healthz":
            self.respond(200, b'{"ok":true}')
            return
        if path == PREFIX + "/status":
            if not self.server.state.bearer_ok(self.headers.get("Authorization", "")):
                self.respond(401, b'{"error":"unauthorized"}')
                return
            self.respond(200, json.dumps(self.server.state.last_result).encode())
            return
        if not path.startswith(PREFIX + "/"):
            self.respond(404, b'{"error":"not_found"}')
            return
        if not self.server.state.cookie_ok(self.headers.get("Cookie", "")):
            self.respond(401, b'{"error":"unauthorized"}')
            return
        suffix = unquote(path[len(PREFIX) + 1:])
        if not suffix or suffix.endswith("/"):
            suffix += "index.html"
        # Exclude .hidden files, tools and generated metadata.
        parts = Path(suffix).parts
        if not parts or any(part in ("..", ".") or part.startswith(".") for part in parts):
            self.respond(404, b'{"error":"not_found"}')
            return
        allowed = suffix == "index.html" or suffix == "photos.json" or (
            parts[0] in ("photos", "baked", "assets")
            and len(parts) > 1
        )
        if not allowed:
            self.respond(404, b'{"error":"not_found"}')
            return
        current = self.server.state.root / "current"
        if not current.is_symlink():
            self.respond(503, b'{"error":"not_ready"}')
            return
        base = current.resolve()
        candidate = (base / suffix).resolve()
        if not candidate.is_relative_to(base) or not candidate.is_file():
            self.respond(404, b'{"error":"not_found"}')
            return
        if candidate.stat().st_size > 25 * 1024 * 1024:
            self.respond(413, b'{"error":"too_large"}')
            return
        mime, _ = mimetypes.guess_type(candidate.name)
        if mime is None:
            mime = "application/octet-stream"
        if mime.startswith("text/") or mime == "application/javascript":
            mime += "; charset=utf-8"
        self.respond(200, candidate.read_bytes(), mime)


class PrivateServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, addr, state):
        super().__init__(addr, Handler)
        self.state = state


def main():
    base = os.environ.get("MUSEUM_EPHEMERA_BASE", "")
    token = os.environ.get("MUSEUM_HER_TOKEN", "")
    root = Path(os.environ.get("MUSEUM_GALLERY_DIR", "/var/lib/museum-private/gallery"))
    repo = Path(__file__).resolve().parent.parent
    state = State(root, token, EphemeraClient(base, token),
                  repo / "sources/shelf-in-the-sky",
                  repo / "sources/ephemera-date")
    port = int(os.environ.get("MUSEUM_BRIDGE_PORT", "8794"))
    server = PrivateServer(("127.0.0.1", port), state)
    print(f"Private museum service on loopback:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
