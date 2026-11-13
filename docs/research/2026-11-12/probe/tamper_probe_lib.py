"""Prevalence of 'test file edited between a failed and a passing test run'.
Counts only. No path, command or text is printed.
    python3 -I tamper_probe.py <repo> [--days N]
"""
import collections, json, os, re, sys, time

TEST_DIR = re.compile(r"(^|/)(tests?|__tests__|spec|specs|Tests|testing|test_data|fixtures?)/")
TEST_FILE = re.compile(r"(^|/)(test_[^/]+\.py|[^/]+_test\.(py|go|rs|rb)|[^/]+\.(test|spec)\.[jt]sx?|[^/]+Tests?\.(swift|java|kt)|conftest\.py)$")
def is_test(p): return bool(TEST_DIR.search(p) or TEST_FILE.search(p))

