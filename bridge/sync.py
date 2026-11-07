#!/usr/bin/env python3
"""Private Ephemera → original Shelf in the Sky gallery.

Only completed, already-visible dates are imported through the *her* API.
Photos and notes remain on a private server; the public GitHub repo contains
no user's media or dates. The original Shelf bake.py produces the picture look.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib import request
from urllib.parse import urlsplit
from PIL import Image, ImageOps, UnidentifiedImageError

try:
    # iPhone photos are frequently HEIC. Ephemera keeps the originals.
    from pillow_heif import register_heif_opener
    register_heif_opener()
except ImportError:
    pass

MAX_IMAGE = 20 * 1024 * 1024

class SyncError(Exception):
    pass

class EphemeraClient:
    def __init__(self, base: str, credential: str):
        parts = urlsplit(base)
        if parts.scheme not in ("https", "http") or not parts.hostname or parts.query or parts.fragment:
            raise ValueError("Invalid Ephemera base URL")
        # HTTP only for private loopback / isolated test instances.
        if parts.scheme == "http" and parts.hostname not in ("127.0.0.1", "localhost", "::1"):
            raise ValueError("Non-local HTTP is not permitted")
        self.base = base.rstrip("/")
        if not credential:
            raise ValueError("Ephemera credential missing")
        self.credential = credential

    def get(self, path: str, max_size=MAX_IMAGE + 1024) -> bytes:
        req = request.Request(
            self.base + path,
            headers={"Authorization": "Bearer " + self.credential, "Accept": "application/json, image/*"},
        )
        try:
            with request.urlopen(req, timeout=25) as res:
                content_length = int(res.headers.get("Content-Length", "0") or 0)
                if content_length > max_size:
                    raise SyncError("response exceeded size limit")
                data = res.read(max_size + 1)
                if len(data) > max_size:
                    raise SyncError("response exceeded size limit")
                return data
        except Exception as exc:
            raise SyncError("Ephemera API failed (no private URL or token logged)") from exc

    def json(self, path: str) -> dict:
        result = json.loads(self.get(path, max_size=4 * 1024 * 1024))
        if not isinstance(result, dict):
            raise SyncError("invalid Ephemera API response")
        return result


def valid_id(value):
    # No path input ever comes from a date title or user supplied filename.
    try:
        value = int(value)
    except (ValueError, TypeError):
        raise SyncError("invalid record ID")
    if value < 1 or value > 10**12:
        raise SyncError("invalid record ID")
    return value


def valid_date(value):
    date = str(value or "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
        raise SyncError("bad date")
    return date


def _make_jpeg(data: bytes, path: Path):
    try:
        image = ImageOps.exif_transpose(Image.open(io.BytesIO(data)))
        image.load()
        if image.width < 1 or image.height < 1 or image.width * image.height > 55_000_000:
            raise SyncError("photo dimensions not supported")
        rgb = image.convert("RGB")
    except (UnidentifiedImageError, OSError) as exc:
        raise SyncError("photo format not supported by Pillow (HEIC needs optional decoder)") from exc
    rgb.save(path, "JPEG", quality=94, optimize=True)
    return rgb.size


def _ticket_image(original_envelope: Path, target: Path):
    # An existing Ephemera image, *not* an invented replacement art style.
    with Image.open(original_envelope) as original:
        w, h = original.size
        crop = original.crop((int(w*.055), int(h*.11), int(w*.94), int(h*.635)))
        # Warm antique treatment only on the representative postcard;
        # original Ephemera pages and graphics remain untouched.
        gray = ImageOps.grayscale(crop)
        paper = ImageOps.colorize(gray, "#4e3f32", "#f2e5c5").convert("RGB")
        paper.save(target, "JPEG", quality=88, optimize=True)


def sync_gallery(api: EphemeraClient, root: Path, source_shelf: Path,
                 source_ephemera: Path) -> dict:
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    shelf_html = source_shelf / "index.html"
    baker = source_shelf / "tools" / "bake.py"
    invitation = source_ephemera / "docs/images/01-envelope.jpg"
    for f in (shelf_html, baker, invitation):
        if not f.is_file():
            raise SyncError("upstream source is unavailable")
    if not (source_shelf / "assets").is_dir():
        raise SyncError("original gallery assets missing")
    plans = api.json("/api/dates").get("plans")
    if not isinstance(plans, list):
        raise SyncError("expected plans array")
    old = root / "current"
    old = old.resolve() if old.is_symlink() else None

    def reuse_private(source: Path, target: Path) -> bool:
        if old is None or not source.is_file():
            return False
        try:
            os.link(source, target)
        except OSError:
            shutil.copy2(source, target)
        return True

    stage = Path(tempfile.mkdtemp(prefix=".gallery-", dir=root))
    try:
        (stage / "photos").mkdir()
        shutil.copytree(source_shelf / "assets", stage / "assets")
        (stage / "tools").mkdir()
        shutil.copyfile(baker, stage / "tools/bake.py")
        # The unchanged original gallery, plus a tiny box-link extension.
        html = shelf_html.read_text(encoding="utf-8")
        anchor = '  tx.scrollTop = 0;'
        if html.count(anchor) != 1:
            raise SyncError("original gallery changed; safe link insertion point missing")
        gallery_link = '''  // Interoperability only: add one link to the existing photo-back text.
  // Paper, motion, colours and all other upstream UI stay exactly as authored.
  if (Number.isSafeInteger(s.boxId) && s.boxId > 0) {
    const goBox = document.createElement("a");
    goBox.href = "zfxf-box://open/" + s.boxId;
    goBox.textContent = "↗ 打开这一天的纪念盒";
    goBox.style.cssText = "display:block;margin-top:1.3em;color:inherit;text-decoration:underline;text-underline-offset:4px;font:inherit;";
    // The original lightbox treats ordinary taps as "flip the paper".
    // Let a real link be tapped without firing the card's pointer handler.
    goBox.addEventListener("pointerdown", e => e.stopPropagation());
    goBox.addEventListener("pointerup", e => e.stopPropagation());
    goBox.addEventListener("click", e => e.stopPropagation());
    tx.append(document.createElement("br"), goBox);
  }
'''
        html = html.replace(anchor, gallery_link + anchor)
        (stage / "index.html").write_text(html, encoding="utf-8")
        count_dates, count_photos, ignored = 0, 0, 0
        linked: dict[str, int] = {}
        for item in plans:
            if not isinstance(item, dict):
                continue
            # Never import preparing, sealed, future, cancelled, or ongoing dates.
            if item.get("cancelled_at") or not (
                item.get("status") == "done" or item.get("closed_at")
            ):
                continue
            plan_id = valid_id(item.get("id"))
            date = valid_date(item.get("date"))
            detailed = api.json(f"/api/dates/{plan_id}")
            if detailed.get("cancelled_at") or not (
                detailed.get("status") == "done" or detailed.get("closed_at")
            ):
                continue
            title = str(detailed.get("title_zh") or detailed.get("title_en") or "我们的约会").strip()
            if not title:
                title = "我们的约会"
            # A keepsake exists even if no photo was uploaded during the date.
            ticket_name = f"{date}_museum_box-{plan_id}.jpg"
            if not reuse_private(
                old / "photos" / ticket_name if old else Path("/nonexistent"),
                stage / "photos" / ticket_name
            ):
                _ticket_image(invitation, stage / "photos" / ticket_name)
            (stage / "photos" / f"{date}_museum_box-{plan_id}.txt").write_text(
                f"**{title}**\n{date}\n一封从 Ephemera 纪念盒寄来的信。\n标签：约会 · 纪念盒\n",
                encoding="utf-8",
            )
            linked[ticket_name] = plan_id
            count_dates += 1
            photos = api.json(f"/api/dates/{plan_id}/her").get("photos")
            if not isinstance(photos, list):
                raise SyncError("expected photos array")
            for photo in photos:
                photo_id = valid_id(photo.get("id"))
                # The authenticated her endpoint filters deleted and unshared photos.
                fname = f"{date}_museum_box-{plan_id}_photo-{photo_id}.jpg"
                dest = stage / "photos" / fname
                previous = old / "photos" / fname if old else Path("/nonexistent")
                if not reuse_private(previous, dest):
                    raw = api.get(f"/api/dates/{plan_id}/her/photo/{photo_id}")
                    try:
                        _make_jpeg(raw, dest)
                    except SyncError:
                        ignored += 1
                        continue
                caption = str(photo.get("caption") or "").strip()
                note = f"**{title}**\n{date}\n"
                if caption:
                    note += caption[:1000] + "\n"
                note += "标签：约会 · 照片\n"
                (stage / "photos" / fname.replace(".jpg", ".txt")).write_text(
                    note, encoding="utf-8",
                )
                linked[fname] = plan_id
                count_photos += 1

        # Reuse originals baked by the original Shelf recipe.
        # A date+planID+photoID is immutable in Ephemera.
        if old is not None:
            baked_cache = old / "baked"
            (stage / "baked").mkdir(exist_ok=True)
            for photo in (stage / "photos").glob("*.jpg"):
                if not (old / "photos" / photo.name).is_file():
                    continue
                base = photo.stem
                variants = [baked_cache / f"{v}-{base}.webp" for v in ("t", "d", "b")]
                if all(x.is_file() for x in variants):
                    for var in variants:
                        reuse_private(var, stage / "baked" / var.name)

        # Run the unchanged upstream image baker. The private snapshot is not
        # uploaded or written back to the public repository.
        subprocess.run(
            [sys.executable, str(stage / "tools/bake.py"), "--group", "month"],
            cwd=stage, stdout=subprocess.DEVNULL, check=True, timeout=180,
        )
        manifest = stage / "photos.json"
        gallery = json.loads(manifest.read_text(encoding="utf-8"))
        for photo in gallery["photos"]:
            photo["boxId"] = linked[photo["file"]]
        manifest.write_text(json.dumps(gallery, ensure_ascii=False, indent=2), encoding="utf-8")
        (stage / "generation.json").write_text(json.dumps({
            "dates": count_dates, "photos": count_photos,
            "keepsakes": count_dates, "unsupported": ignored,
        }), encoding="utf-8")
        # Atomic symlink switch: existing readers continue on the old generation.
        tmp_link = root / ".next"
        if tmp_link.is_symlink():
            tmp_link.unlink()
        tmp_link.symlink_to(stage.name, target_is_directory=True)
        os.replace(tmp_link, root / "current")
        # Keep prior generations to avoid breaking requests in flight; keep
        # space under control on small VPS systems.
        generations = sorted(
            (p for p in root.glob(".gallery-*") if p.is_dir()),
            key=lambda p: p.stat().st_mtime, reverse=True,
        )
        for past in generations[3:]:
            shutil.rmtree(past)
        return {"dates": count_dates, "photos": count_photos,
                "keepsakes": count_dates, "unsupported": ignored}
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--api-base", default=os.environ.get("MUSEUM_EPHEMERA_BASE", ""))
    ap.add_argument("--shelf", default="sources/shelf-in-the-sky")
    ap.add_argument("--ephemera", default="sources/ephemera-date")
    args = ap.parse_args()
    token = os.environ.get("MUSEUM_HER_TOKEN", "")
    try:
        out = sync_gallery(EphemeraClient(args.api_base, token),
                           Path(args.root), Path(args.shelf), Path(args.ephemera))
        print(json.dumps(out, ensure_ascii=False))
    except Exception as exc:
        # Avoid leaking any addresses/credentials via exception chain.
        print(f"Museum sync failed: {type(exc).__name__}", file=sys.stderr)
        raise SystemExit(1)

if __name__ == "__main__":
    main()
