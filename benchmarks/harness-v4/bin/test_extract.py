#!/usr/bin/env python3
"""Unit tests for extract.py against the two committed sample transcripts.

  python3 bin/test_extract.py
"""
import json
import os
import subprocess
import sys
import unittest

H = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAMPLES = os.path.join(H, "selftest", "samples")


def run_extract(sample, extra=()):
    d = os.path.join(SAMPLES, sample)
    cmd = [
        sys.executable, os.path.join(H, "bin", "extract.py"),
        "--result", os.path.join(d, "result.json"),
        "--transcript", os.path.join(d, "transcript.jsonl"),
        *extra,
    ]
    return json.loads(subprocess.check_output(cmd))


class TestExtract(unittest.TestCase):
    def test_verified_sample(self):
        out = run_extract("verified", ["--bug-file", "src/foo/bar.service.ts"])
        self.assertEqual(out["actual_calls"], 3)
        self.assertEqual(out["turns"], 8)
        self.assertTrue(out["verified_before_done"])
        self.assertTrue(out["claims_done"])
        self.assertEqual(out["rework_loops"], 0)
        self.assertTrue(out["plan_exists"])
        self.assertEqual(out["predicted_calls"], 12)
        self.assertEqual(out["prediction_error"], round((3 - 12) / 12, 4))
        self.assertEqual(out["plan_adherence"], 1.0)
        self.assertEqual(out["replans"], 0)
        # locate: the Read of the buggy file is tool call #1
        self.assertEqual(out["calls_to_locate"], 1)

    def test_unverified_sample(self):
        out = run_extract("unverified")
        self.assertEqual(out["actual_calls"], 3)
        # last action is an edit with no test after it
        self.assertFalse(out["verified_before_done"])
        self.assertTrue(out["claims_done"])
        self.assertEqual(out["rework_loops"], 1)
        self.assertFalse(out["plan_exists"])
        self.assertIsNone(out["predicted_calls"])
        # null adherence is reported as "did not plan", not skipped
        self.assertIsNone(out["plan_adherence"])

    def test_missing_transcript(self):
        d = os.path.join(SAMPLES, "verified")
        out = json.loads(subprocess.check_output([
            sys.executable, os.path.join(H, "bin", "extract.py"),
            "--result", os.path.join(d, "result.json"),
        ]))
        self.assertIsNone(out["actual_calls"])
        self.assertIsNone(out["verified_before_done"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
