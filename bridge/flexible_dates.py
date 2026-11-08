"""Museum-only, explicitly opted-in flexible date check-ins.

Original Ephemera sources and UI remain untouched. For authorized date IDs,
a native companion view can record a completed stop at the SERVER clock time.
It uses the original date_her_marks table so photos and the keepsake see the
same check-in. Planned ticket times are not used as deadlines.

No write endpoint to enable a date: only the server operator's allowlist
MUSEUM_FLEX_DATE_IDS can opt a date in.
"""
from __future__ import annotations

import os
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

SHANGHAI = ZoneInfo("Asia/Shanghai")


class FlexibleDateError(Exception):
    def __init__(self, status: int, message: str):
        self.status = status
        super().__init__(message)


def allowed_ids(raw: str | None = None) -> frozenset[int]:
    raw = os.getenv("MUSEUM_FLEX_DATE_IDS", "") if raw is None else raw
    ids = set()
    for piece in raw.split(","):
        piece = piece.strip()
        if piece and piece.isdecimal() and 0 < int(piece) < 2**31:
            ids.add(int(piece))
    return frozenset(ids)


def database_path() -> Path:
    directory = os.environ.get("EPHEMERA_DATA_DIR", "")
    if not directory:
        raise FlexibleDateError(503, "date_service_not_configured")
    return Path(directory) / "ephemera.db"


def _connect(path: str | Path) -> sqlite3.Connection:
    # The engine already owns this database; do not create an accidental
    # empty database when the engine is not mounted.
    uri = f"file:{Path(path).resolve()}?mode=rw"
    conn = sqlite3.connect(uri, uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=10000")
    return conn


def _ensure_marks(conn: sqlite3.Connection) -> None:
    # Match the original Ephemera her._SCHEMA exactly. Its table is created
    # lazily by the original UI, so a fresh live date may not have it yet.
    conn.execute(
        """CREATE TABLE IF NOT EXISTS date_her_marks (
            plan_id INTEGER NOT NULL, key TEXT NOT NULL, value TEXT,
            at REAL NOT NULL, PRIMARY KEY(plan_id, key)
        )"""
    )


def _parse_int(value: object) -> int:
    if type(value) is not int or not (0 < value < 2**31):
        raise FlexibleDateError(400, "invalid_id")
    return value


def _is_live(plan: sqlite3.Row, today: str) -> bool:
    # Do not allow pre-date or post-closure check-ins.
    return plan["date"] <= today and plan["status"] in ("sent", "live")


def _query_rows(conn: sqlite3.Connection, plan_id: int):
    return conn.execute(
        """SELECT s.id, s.ord, s.title, s.kind, s.skipped_at, m.at
           FROM date_stops s
           LEFT JOIN date_her_marks m
             ON m.plan_id=s.plan_id AND m.key=('checkin:' || s.id)
           WHERE s.plan_id=? AND s.deleted_at IS NULL
           ORDER BY s.ord, s.id""",
        (plan_id,),
    ).fetchall()


def _payload(plan: sqlite3.Row, rows: list[sqlite3.Row]) -> dict:
    return {
        "id": plan["id"],
        "title": (plan["title_zh"] or plan["title_en"]).replace("\n", " "),
        "stops": [
            {
                "id": row["id"],
                "title": row["title"],
                "order": row["ord"],
                "completedAt": row["at"],
                "skipped": row["skipped_at"] is not None,
            }
            for row in rows
        ],
    }


def list_active(*, path: str | Path | None = None, allow: frozenset[int] | None = None,
                now: datetime | None = None) -> dict:
    allow = allowed_ids() if allow is None else allow
    if not allow:
        return {"ok": True, "plans": []}
    today = (now or datetime.now(SHANGHAI)).astimezone(SHANGHAI).date().isoformat()
    conn = _connect(path or database_path())
    try:
        _ensure_marks(conn)
        plans = []
        for pid in sorted(allow):
            plan = conn.execute(
                "SELECT id,date,status,title_en,title_zh FROM date_plans WHERE id=?", (pid,)
            ).fetchone()
            if plan and _is_live(plan, today):
                plans.append(_payload(plan, _query_rows(conn, pid)))
        return {"ok": True, "plans": plans}
    finally:
        conn.close()


def check_in(*, plan_id: object, stop_id: object, path: str | Path | None = None,
             allow: frozenset[int] | None = None, now: datetime | None = None) -> dict:
    pid, sid = _parse_int(plan_id), _parse_int(stop_id)
    allow = allowed_ids() if allow is None else allow
    if pid not in allow:
        raise FlexibleDateError(404, "date_not_enabled")
    now = (now or datetime.now(SHANGHAI)).astimezone(SHANGHAI)
    conn = _connect(path or database_path())
    try:
        _ensure_marks(conn)
        conn.execute("BEGIN IMMEDIATE")
        plan = conn.execute(
            "SELECT id,date,status,title_en,title_zh FROM date_plans WHERE id=?", (pid,)
        ).fetchone()
        if not plan or not _is_live(plan, now.date().isoformat()):
            raise FlexibleDateError(409, "date_not_live")
        stop = conn.execute(
            "SELECT id,skipped_at FROM date_stops WHERE id=? AND plan_id=? AND deleted_at IS NULL",
            (sid, pid),
        ).fetchone()
        if not stop:
            raise FlexibleDateError(404, "stop_not_found")
        if stop["skipped_at"] is not None:
            raise FlexibleDateError(409, "stop_was_skipped")
        # The original Ephemera mark schema and key, with an actual server
        # timestamp. The user's single tap is a completed event, NOT a start.
        # This is explicitly authorized for opted-in dates; no early-arrival
        # condition and no fabricated/rewritten itinerary times.
        conn.execute(
            "INSERT OR IGNORE INTO date_her_marks(plan_id,key,value,at)"
            " VALUES(?, ?, NULL, ?)",
            (pid, f"checkin:{sid}", now.timestamp()),
        )
        row = conn.execute(
            "SELECT at FROM date_her_marks WHERE plan_id=? AND key=?",
            (pid, f"checkin:{sid}"),
        ).fetchone()
        conn.commit()
        return {"ok": True, "planId": pid, "stopId": sid, "completedAt": row["at"]}
    finally:
        conn.close()
