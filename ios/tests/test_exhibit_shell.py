"""Regression checks for the native Museum exhibition shell.
The simulator build verifies Swift syntax; these checks guard the host flow.
"""
import pathlib
import unittest

HOME = pathlib.Path(__file__).resolve().parents[1] / "Museum" / "MuseumHomeView.swift"
text = HOME.read_text(encoding="utf-8")


class ExhibitionShellTests(unittest.TestCase):
    def test_no_custom_native_header_or_duplicate_demo_fast_forward(self):
        self.assertNotIn('Label("试玩 · 快进"', text)
        self.assertNotIn("func advanceDemo()", text)
        self.assertNotIn('data-testid="demo-step"', text)
        self.assertNotIn("frame(height: 56)", text)

    def test_all_hosted_exhibits_and_private_date_have_bookmark(self):
        self.assertEqual(text.count("MuseumBookmark(exitTitle:"), 2)
        self.assertIn('museum-bookmark-toggle', text)
        self.assertIn('museum-bookmark-continue', text)
        self.assertIn('museum-bookmark-exit', text)
        self.assertIn('EphemeraPage(config: host.config', text)
        self.assertIn('.ignoresSafeArea(edges: .bottom)', text)

    def test_original_demo_button_and_second_bouquet_routes_survive(self):
        self.assertIn('exhibit = .datesDemo', text)
        self.assertIn('if current == .datesDemo && returnWithFlowers', text)
        self.assertIn('exhibit = .afterFlower', text)
        self.assertIn('.onChange(of: host.pageOpen)', text)
        self.assertIn('host.pageOpen = false', text)
        self.assertIn('onOpenDemoDates:', text)
        self.assertIn('onOpenLiveDates:', text)
        self.assertNotIn('visibility: hidden !important', text)


if __name__ == "__main__":
    unittest.main()
