"""Checks that the documentation points at files that exist.

Run from anywhere:  python3 tests/test_docs.py
Looks at every local image and link in README.md, CHANGELOG.md and docs/*.md.
"""
import glob
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOCS = [os.path.join(ROOT, "README.md"), os.path.join(ROOT, "CHANGELOG.md")] + glob.glob(os.path.join(ROOT, "docs", "*.md"))
LINK = re.compile(r"\]\(([^)\s]+)")


class LocalLinks(unittest.TestCase):
    def test_every_local_link_exists(self):
        missing = []
        for doc in DOCS:
            base = os.path.dirname(doc)
            with open(doc, encoding="utf-8") as f:
                for target in LINK.findall(f.read()):
                    if re.match(r"^(https?:|mailto:|#)", target):
                        continue
                    path = target.split("#", 1)[0]
                    if path and not os.path.exists(os.path.normpath(os.path.join(base, path))):
                        missing.append(f"{os.path.relpath(doc, ROOT)} -> {target}")
        self.assertEqual(missing, [], "documentation links to files that do not exist")


if __name__ == "__main__":
    unittest.main()
