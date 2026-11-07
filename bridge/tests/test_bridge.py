import io
import json
import sys
from pathlib import Path
import tempfile
import threading
import unittest
from urllib import request, error

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "bridge"))
from sync import sync_gallery, EphemeraClient, SyncError
from server import State, PrivateServer


def jpg_bytes():
    img = Image.new("RGB", (90, 100), "#e4b8aa")
    out = io.BytesIO()
    img.save(out, "JPEG")
    return out.getvalue()


class MockEphemera:
    def __init__(self):
        self.photos = [
            {"id": 21, "caption": "约会留影", "stop_id": 12, "created_at": 0.0}
        ]
        self.items = jpg_bytes()
        self.paths = []

    def json(self, path):
        self.paths.append(path)
        if path == "/api/dates":
            return {"plans": [
                {"id": 7, "status": "done", "date": "2026-10-27", "closed_at": 1690000000},
                {"id": 9, "status": "preparing", "date": "2026-12-14", "closed_at": None},
                {"id": 12, "status": "done", "date": "2026-11-03", "cancelled_at": 1},
            ]}
        if path == "/api/dates/7":
            return {"id": 7, "status": "done", "date": "2026-10-27",
                    "closed_at": 1690000000, "title_zh": "我们的测试约会"}
        if path == "/api/dates/7/her":
            return {"photos": self.photos}
        raise AssertionError("private unfinished date was requested: " + path)

    def get(self, path):
        self.paths.append(path)
        if path == "/api/dates/7/her/photo/21":
            return self.items
        raise AssertionError("unexpected photo request: " + path)


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.api = MockEphemera()

    def sync(self):
        return sync_gallery(
            self.api, self.root, REPO / "sources/shelf-in-the-sky",
            REPO / "sources/ephemera-date"
        )

    def test_imports_only_closed_dates_and_exact_upstream_bake(self):
        result = self.sync()
        self.assertEqual(result, {"dates": 1, "photos": 1, "keepsakes": 1, "unsupported": 0})
        current = (self.root / "current").resolve()
        items = json.loads((current / "photos.json").read_text())["photos"]
        self.assertEqual(len(items), 2)  # one physical photo + invitation
        self.assertEqual({i["boxId"] for i in items}, {7})
        self.assertTrue(all((current / "baked" /
                            ("d-" + i["file"].rsplit(".", 1)[0] + ".webp")).exists() for i in items))
        html = (current / "index.html").read_text()
        self.assertIn("zfxf-box://open/", html)
        self.assertIn("↗ 打开这一天的纪念盒", html)
        self.assertNotIn("/api/dates/9/her", self.api.paths)
        self.assertNotIn("/api/dates/12/her", self.api.paths)

    def test_deletions_do_not_leave_orphaned_gallery_photos(self):
        self.sync()
        self.api.photos = []
        self.sync()
        current = (self.root / "current").resolve()
        items = json.loads((current / "photos.json").read_text())["photos"]
        self.assertEqual(len(items), 1)
        self.assertTrue(items[0]["file"].endswith("box-7.jpg"))
        self.assertTrue((current / "photos" / items[0]["file"]).exists())
        self.assertEqual(len(list((current / "photos").glob("*photo-21*"))), 0)

    def test_gallery_requires_session_cookie_and_token(self):
        self.sync()
        state = State(self.root, "unit-test-credential",
                      EphemeraClient("http://127.0.0.1:8793", "unit-test-credential"),
                      REPO / "sources/shelf-in-the-sky",
                      REPO / "sources/ephemera-date")
        srv = PrivateServer(("127.0.0.1", 0), state)
        th = threading.Thread(target=srv.serve_forever, daemon=True)
        th.start()
        self.addCleanup(srv.server_close)
        self.addCleanup(srv.shutdown)
        base = f"http://127.0.0.1:{srv.server_port}/museum-gallery"
        def get(path, cookie=""):
            req = request.Request(base + path, headers={"Cookie": cookie})
            try:
                with request.urlopen(req, timeout=3) as response:
                    return response.status, response.read()
            except error.HTTPError as e:
                return e.code, e.read()

        self.assertEqual(get("/")[0], 401)
        self.assertEqual(get("/photos.json")[0], 401)
        req = request.Request(
            base + "/session", data=b"", method="POST",
            headers={"Authorization": "Bearer bad"}
        )
        with self.assertRaises(error.HTTPError) as rejected:
            request.urlopen(req, timeout=3)
        self.assertEqual(rejected.exception.code, 401)
        req.add_header("Authorization", "Bearer unit-test-credential")
        with request.urlopen(req, timeout=3) as accepted:
            self.assertEqual(accepted.status, 204)
            cookie = accepted.headers["Set-Cookie"]
        self.assertIn("HttpOnly", cookie)
        self.assertIn("Secure", cookie)
        cookie = cookie.split(";", 1)[0]
        self.assertEqual(get("/photos.json", cookie)[0], 200)
        self.assertEqual(get("/assets/sky.webp", cookie)[0], 200)
        self.assertEqual(get("/../.env", cookie)[0], 404)
        self.assertEqual(get("/tools/bake.py", cookie)[0], 404)
        self.assertEqual(get("/generation.json", cookie)[0], 404)


if __name__ == "__main__":
    unittest.main(verbosity=2)
