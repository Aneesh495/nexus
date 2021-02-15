#!/usr/bin/env python3
"""
Verification script: Ensure zero em dashes or en dashes exist in the codebase.
Strict requirement: DO NOT use em dashes in comments, code, or documentation.
"""

import os
import sys

EXCLUDED_DIRS = {".git", ".pytest_cache", "__pycache__", "build", "dist", "bin", "target", ".gradle"}
EXCLUDED_EXTS = {".pod", ".class", ".pyc", ".o", ".so", ".dylib", ".a", ".png", ".jpg", ".ico", ".wal", ".snap"}

FORBIDDEN_CHARS = {
    "\u2014": "EM DASH (U+2014)",
    "\u2013": "EN DASH (U+2013)",
}

def verify_files(root_dir):
    violations = []
    total_files = 0
    total_lines = 0

    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS]
        for file in files:
            ext = os.path.splitext(file)[1].lower()
            if ext in EXCLUDED_EXTS:
                continue

            path = os.path.join(root, file)
            # Skip self to avoid detecting literal check definitions in forbidden char map
            if os.path.abspath(path) == os.path.abspath(__file__):
                continue

            total_files += 1
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    for line_no, line in enumerate(f, start=1):
                        total_lines += 1
                        for char, name in FORBIDDEN_CHARS.items():
                            if char in line:
                                violations.append((path, line_no, name, line.strip()))
            except Exception as e:
                print(f"Warning: Could not read {path}: {e}")

    print(f"Scanned {total_files} files ({total_lines} lines).")
    if violations:
        print(f"FAILURE: Found {len(violations)} forbidden dash characters:")
        for path, line_no, name, preview in violations:
            print(f"  {path}:{line_no}: Found {name}")
            print(f"    Line: {preview}")
        sys.exit(1)
    else:
        print("SUCCESS: Zero em dashes or en dashes found across all repository files.")
        sys.exit(0)

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    verify_files(target)
