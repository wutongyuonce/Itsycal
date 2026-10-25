#!/usr/bin/env python3
"""Install an already verified app with a recoverable directory swap."""
import argparse
import ctypes
import os
import plistlib
import signal
import shutil
import subprocess
import sys
import time

RENAME_SWAP = 0x2


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def version(app: str) -> str:
    with open(os.path.join(app, 'Contents', 'Info.plist'), 'rb') as handle:
        return plistlib.load(handle)['CFBundleVersion']


def stop(path: str, name: str) -> None:
    pids = subprocess.run(['pgrep', '-f', f'^{path}'], text=True, capture_output=True).stdout.split()
    for pid in pids:
        try:
            os.kill(int(pid), signal.SIGTERM)
        except ProcessLookupError:
            continue
        for _ in range(30):
            try:
                os.kill(int(pid), 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            try:
                os.kill(int(pid), signal.SIGKILL)
            except ProcessLookupError:
                continue
            for _ in range(20):
                try:
                    os.kill(int(pid), 0)
                except ProcessLookupError:
                    break
                time.sleep(0.1)
            else:
                fail(f'{name} process {pid} did not exit; refusing to replace the app.')


def swap(first: str, second: str) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renameatx_np(-2, first.encode(), -2, second.encode(), RENAME_SWAP) != 0:
        fail(f'Atomic swap failed: {os.strerror(ctypes.get_errno())}')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True)
    parser.add_argument('--stage', required=True)
    parser.add_argument('--backup', required=True)
    args = parser.parse_args()

    # A signal during the transaction is deferred until the old and new bundles
    # are both safe on disk. SIGKILL still leaves a recoverable backup path.
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, signal.SIG_IGN)

    stop(os.path.join(args.app, 'Contents', 'MacOS', 'Itsycal'), 'Itsycal')
    stop(os.path.join(args.app, 'Contents', 'PlugIns', 'WeekWidget.appex', 'Contents', 'MacOS', 'WeekWidget'), 'Widget')

    had_old = os.path.exists(args.app)
    backup_app = os.path.join(args.backup, 'Itsycal Week.app')
    if had_old:
        old = version(args.app)
        # One filesystem operation: after this, neither path is ever missing.
        swap(args.app, args.stage)
        os.rename(args.stage, backup_app)  # old bundle now in backup
    else:
        old = None
        os.rename(args.stage, args.app)
    try:
        proc = subprocess.run(['codesign', '--verify', '--deep', '--strict', args.app],
                              text=True, capture_output=True)
        if proc.returncode != 0:
            fail('Signature verification failed after install: ' + proc.stderr.strip())
        if version(args.app) == old:
            fail('Installed bundle has the same build as the previous app.')
    except BaseException:
        shutil.rmtree(args.app, ignore_errors=True)
        if had_old:
            os.rename(backup_app, args.app)
        raise
    print(f'Installed {args.app}')


if __name__ == '__main__':
    main()
