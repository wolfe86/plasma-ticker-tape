"""Checks the watchlist key-level rule (package/contents/ui/levels.js).

Run from anywhere:  python3 tests/test_levels.py
The cases are in levels_cases.js; they need Node.js and are skipped without it.
"""
import json
import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class Levels(unittest.TestCase):
    def test_cases(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js not installed")
        out = subprocess.run([node, os.path.join(HERE, "run_cases.js"), "levels.js", os.path.join(HERE, "levels_cases.js")],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        res = json.loads(out.stdout)
        self.assertEqual(res["failures"], [])
        self.assertGreater(res["passed"], 15)


if __name__ == "__main__":
    unittest.main()
