#!/usr/bin/env python3
"""Verify an installed desktop executable remains alive for five seconds."""
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit('Usage: smoke_desktop.py /path/to/desktop-executable')
with tempfile.TemporaryFile() as output:
    process = subprocess.Popen([sys.argv[1]], stdout=output, stderr=output)
    try:
        try:
            code = process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            print('Desktop startup smoke passed (alive after 5 seconds)')
        else:
            output.seek(0)
            sys.stderr.write(output.read().decode('utf-8', errors='replace'))
            raise SystemExit(f'Desktop exited during startup: {code}')
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
