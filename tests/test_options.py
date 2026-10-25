"""Checks the options maths and chain readings (package/contents/ui/options.js).

Run from anywhere:  python3 tests/test_options.py
The cases are in options_cases.js; they need Node.js and are skipped without it.
"""
import json
import os
import shutil
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class Options(unittest.TestCase):
    def test_cases(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js not installed")
        out = subprocess.run([node, os.path.join(HERE, "run_cases.js"), "options.js", os.path.join(HERE, "options_cases.js")],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        res = json.loads(out.stdout)
        self.assertEqual(res["failures"], [])
        self.assertGreater(res["passed"], 30)


if __name__ == "__main__":
    unittest.main()
