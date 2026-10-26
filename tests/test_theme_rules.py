"""Checks the theme rules: patterns, the runner test, and heat from the record.

Run from anywhere:  python3 tests/test_theme_rules.py
Needs Node.js (theme_rules_cases.js loads themes.js the way the widget does).
"""
import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class ThemeRules(unittest.TestCase):
    def test_cases(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js is not installed")
        out = subprocess.run([node, os.path.join(HERE, "theme_rules_cases.js")], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)


if __name__ == "__main__":
    unittest.main()
