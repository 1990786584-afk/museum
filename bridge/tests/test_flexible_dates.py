import sqlite3
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from bridge.flexible_dates import FlexibleDateError, check_in, list_active

TZ = ZoneInfo("Asia/Shanghai")


class FlexibleDatesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "ephemera.db"
        with sqlite3.connect(self.path) as db:
            db.executescript("""
              CREATE TABLE date_plans(id INTEGER PRIMARY KEY, date TEXT,
                status TEXT, title_en TEXT, title_zh TEXT);
              CREATE TABLE date_stops(id INTEGER PRIMARY KEY, plan_id INTEGER,
                ord INTEGER, title TEXT, kind TEXT, skipped_at REAL, deleted_at REAL);
              CREATE TABLE date_her_marks(plan_id INTEGER, key TEXT,
                value TEXT, at REAL, PRIMARY KEY(plan_id,key));
              INSERT INTO date_plans VALUES(2,'2026-11-08','live','A Date','校园约会');
              INSERT INTO date_plans VALUES(3,'2026-12-14','draft','Second Winter','两周年');
              INSERT INTO date_stops VALUES(20,2,1,'洗头完成','train',NULL,NULL);
              INSERT INTO date_stops VALUES(21,2,2,'去学校','moment',NULL,NULL);
              INSERT INTO date_stops VALUES(22,2,3,'跳过','moment',123,NULL);
            """)
        self.now = datetime(2026, 11, 8, 15, 0, tzinfo=TZ)

    def test_no_early_arrival_gate_and_actual_server_time(self):
        a = check_in(plan_id=2, stop_id=20, path=self.path, allow=frozenset({2}),
                     now=self.now)
        self.assertEqual(a["completedAt"], self.now.timestamp())
        self.assertEqual(list_active(path=self.path, allow=frozenset({2}), now=self.now)["plans"][0]["stops"][0]["completedAt"],
                         self.now.timestamp())
        # Repeated taps never overwrite the actual first completion.
        b = check_in(plan_id=2, stop_id=20, path=self.path, allow=frozenset({2}),
                     now=datetime(2026, 11, 8, 18, 0, tzinfo=TZ))
        self.assertEqual(a["completedAt"], b["completedAt"])

    def test_delay_and_out_of_order_are_both_valid(self):
        later = datetime(2026, 11, 9, 1, 30, tzinfo=TZ)
        result = check_in(plan_id=2, stop_id=21, path=self.path, allow=frozenset({2}), now=later)
        self.assertEqual(result["completedAt"], later.timestamp())
        self.assertTrue(result["ok"])

    def test_no_leakage_to_non_opted_in_or_unstarted_date(self):
        with self.assertRaises(FlexibleDateError):
            check_in(plan_id=3, stop_id=20, path=self.path, allow=frozenset({2}), now=self.now)
        with self.assertRaises(FlexibleDateError):
            check_in(plan_id=3, stop_id=20, path=self.path, allow=frozenset({3}), now=self.now)
        with self.assertRaises(FlexibleDateError):
            check_in(plan_id=2, stop_id=22, path=self.path, allow=frozenset({2}), now=self.now)
        with self.assertRaises(FlexibleDateError):
            check_in(plan_id=2, stop_id=999, path=self.path, allow=frozenset({2}), now=self.now)
        self.assertEqual(list_active(path=self.path, allow=frozenset(), now=self.now)["plans"], [])

    def test_original_marks_table_is_initialized_when_missing(self):
        with sqlite3.connect(self.path) as db:
            db.execute("DROP TABLE date_her_marks")
        result = list_active(path=self.path, allow=frozenset({2}), now=self.now)
        self.assertEqual(len(result["plans"][0]["stops"]), 3)
        item = check_in(plan_id=2, stop_id=20, path=self.path, allow=frozenset({2}), now=self.now)
        self.assertEqual(item["completedAt"], self.now.timestamp())

    def test_close_prevents_new_checkin(self):
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE date_plans SET status='done' WHERE id=2")
        with self.assertRaises(FlexibleDateError):
            check_in(plan_id=2, stop_id=20, path=self.path, allow=frozenset({2}), now=self.now)


if __name__ == "__main__":
    unittest.main()
