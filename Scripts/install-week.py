#!/usr/bin/env python3
"""Install an already verified app with a recoverable directory swap."""
import argparse
import ctypes
import os
import plistlib
import re
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


def stop(pattern: str, name: str) -> None:
    """Stop this user's processes whose command line matches pattern."""
    pids = subprocess.run(['pgrep', '-U', str(os.getuid()), '-f', pattern],
                          text=True, capture_output=True).stdout.split()
    for pid in pids:
        try:
            os.kill(int(pid), signal.SIGTERM)
        except ProcessLookupError:
            continue
        except PermissionError:
            fail(f'Cannot stop {name} process {pid}; refusing to replace the app.')
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

    # INT/TERM/HUP are ignored (not deferred) for the whole run, so stopping,
    # swapping and rolling back are never interrupted halfway. SIGKILL can
    # still interrupt; the shell wrapper then keeps any leftover bundles.
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, signal.SIG_IGN)

    had_old = os.path.exists(args.app)
    backup_app = os.path.join(args.backup, os.path.basename(args.app))
    try:
        # Everything before the swap leaves the installed app untouched.
        if had_old and version(args.app) == version(args.stage):
            fail('The built bundle has the same build as the installed app.')
        stop('^' + re.escape(os.path.join(args.app, 'Contents', 'MacOS', 'Itsycal')) + '( |$)', 'Itsycal')
        # Any embedded extension, including ones a newer build renamed or removed.
        stop('^' + re.escape(os.path.join(args.app, 'Contents', 'PlugIns', '')), 'Widget')
        if had_old:
            # One filesystem operation: after this, neither path is ever missing.
            swap(args.app, args.stage)
        else:
            os.rename(args.stage, args.app)
    except BaseException:
        shutil.rmtree(args.stage, ignore_errors=True)
        raise
    if had_old:
        os.rename(args.stage, backup_app)  # old bundle now in backup
    try:
        proc = subprocess.run(['codesign', '--verify', '--deep', '--strict', args.app],
                              text=True, capture_output=True)
        if proc.returncode != 0:
            fail('Signature verification failed after install: ' + proc.stderr.strip())
    except BaseException:
        shutil.rmtree(args.app, ignore_errors=True)
        if had_old:
            os.rename(backup_app, args.app)
        raise
    print(f'Installed {args.app}')


if __name__ == '__main__':
    main()
