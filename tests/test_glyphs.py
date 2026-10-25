"""Checks the widget's icon library and theme catalogues.

Run from anywhere:  python3 tests/test_glyphs.py
Needs Node.js (it loads themes.js with export_themes.js, the way the widget does).
"""
import json
import os
import re
import shutil
import subprocess
import unittest
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))


def export():
    node = shutil.which("node")
    if not node:
        raise unittest.SkipTest("Node.js is not installed")
    out = subprocess.run([node, os.path.join(HERE, "export_themes.js")],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


class GlyphLibrary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lib = export()

    def test_every_glyph_is_well_formed_svg(self):
        # The widget fills {F}, {C} and {B} in each fragment, then wraps it in an <svg>.
        for name, frag in self.lib["glyphs"].items():
            for fill, colour, back in (("none", "#d8dce0", "#1b1e20"), ("#e24c40", "#e24c40", "#1b1e20")):
                body = frag.replace("{F}", fill).replace("{C}", colour).replace("{B}", back)
                svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">{body}</svg>'
                try:
                    ET.fromstring(svg)
                except ET.ParseError as e:
                    self.fail(f"glyph '{name}' is not well-formed SVG: {e}")

    def test_every_catalogue_glyph_exists(self):
        used = [(t["id"], t["glyph"]) for t in self.lib["sectors"] + self.lib["crypto"] + self.lib["starters"]]
        missing = [(i, g) for i, g in used if g not in self.lib["glyphs"]]
        self.assertEqual(missing, [], "catalogue entries point at glyphs that do not exist")

    def test_glyph_names_match_library(self):
        self.assertEqual(sorted(self.lib["glyphNames"]), sorted(self.lib["glyphs"].keys()))

    def test_new_glyphs_present(self):
        for name in ("tower", "vault", "anon", "drone", "tank", "ai", "bitcoin", "mining", "cannabis"):
            self.assertIn(name, self.lib["glyphs"])

    def test_helper_functions(self):
        c = self.lib["checks"]
        self.assertTrue(c["iconIsSvgUrl"], "icon() should return an SVG data URL")
        self.assertTrue(c["unknownGlyphFallsBackToDot"], "an unknown glyph should draw the dot")
        self.assertEqual(c["glyphNameDefault"], "chip")
        self.assertEqual(c["glyphNameOverride"], "tank", "a glyph chosen in Settings should win")
        self.assertEqual(c["glyphNameIgnoresUploadOnly"], "chip", "an uploaded icon alone should not change the glyph")
        self.assertEqual(c["classifyGaming"], "c-gaming")
        self.assertIsNone(c["classifyNone"])
        self.assertIsNone(c["customNeedsIcon"], "a glyph-only override is not an uploaded icon")


class ScannerFiles(unittest.TestCase):
    def test_python_files_compile(self):
        import py_compile
        root = os.path.join(HERE, "..", "package", "contents", "code")
        for dirpath, _, files in os.walk(root):
            for f in files:
                if f.endswith(".py"):
                    py_compile.compile(os.path.join(dirpath, f), doraise=True)

    def test_bridge_unknown_command_is_json_error(self):
        bridge = os.path.join(HERE, "..", "package", "contents", "code", "scannerbridge.py")
        out = subprocess.run(["python3", bridge, "", "nosuchcommand"], capture_output=True, text=True, timeout=30).stdout
        self.assertIn("error", json.loads(out))

    def test_bridge_without_arguments_prints_usage(self):
        bridge = os.path.join(HERE, "..", "package", "contents", "code", "scannerbridge.py")
        out = subprocess.run(["python3", bridge], capture_output=True, text=True, timeout=30).stdout
        self.assertIn("usage", json.loads(out)["error"].lower())


if __name__ == "__main__":
    unittest.main()
