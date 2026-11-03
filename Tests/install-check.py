#!/usr/bin/env python3
"""Exercise install-week.py against temporary bundles, never the live app."""
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

installer = Path(__file__).resolve().parent.parent / 'Scripts' / 'install-week.py'


def make_app(root: Path, bundle: str, build: str, marker: str) -> None:
    contents = root / 'Contents'
    contents.mkdir(parents=True)
    with open(contents / 'Info.plist', 'wb') as handle:
        plistlib.dump({'CFBundleIdentifier': bundle, 'CFBundleVersion': build,
                       'CFBundleExecutable': 'stub', 'CFBundlePackageType': 'APPL'}, handle)
    macos = contents / 'MacOS'
    macos.mkdir()
    shutil.copy('/usr/bin/true', macos / 'stub')
    subprocess.run(['chmod', '+x', str(macos / 'stub')], check=True)
    resources = contents / 'Resources'
    resources.mkdir()
    (resources / marker).write_text(marker)
    subprocess.run(['codesign', '--force', '--sign', '-', str(root)], check=True,
                   capture_output=True)


def run(app: Path, stage: Path, backup: Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(installer), '--app', str(app),
                           '--stage', str(stage), '--backup', str(backup)],
                          text=True, capture_output=True)


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary) / 'Applications'
    root.mkdir()
    backup = Path(temporary) / 'backup'
    backup.mkdir()
    app, stage = root / 'Itsycal.app', root / '.new.app'
    make_app(app, 'com.example.week', '1', 'old')
    make_app(stage, 'com.example.week', '2', 'new')
    result = run(app, stage, backup)
    assert result.returncode == 0, result.stderr
    assert (app / 'Contents' / 'Resources' / 'new').exists()
    assert (backup / 'Itsycal.app' / 'Contents' / 'Resources' / 'old').exists()
    assert not stage.exists()

    # The same build is rejected before anything is replaced.
    same = root / '.same.app'
    make_app(same, 'com.example.week', '2', 'same')
    same_backup = Path(temporary) / 'same-backup'
    same_backup.mkdir()
    result = run(app, same, same_backup)
    assert result.returncode != 0
    assert (app / 'Contents' / 'Resources' / 'new').exists(), 'installed bundle must be untouched'
    assert not same.exists() and not any(same_backup.iterdir()), 'rejected bundle is cleaned up'

    # Failed post-swap verification restores the old bundle and removes the new.
    bad = root / '.bad.app'
    make_app(bad, 'com.example.week', '3', 'bad')
    (bad / 'Contents' / 'Resources' / 'bad').write_text('tampered')  # breaks the signature seal
    bad_backup = Path(temporary) / 'bad-backup'
    bad_backup.mkdir()
    result = run(app, bad, bad_backup)
    assert result.returncode != 0 and 'Signature verification failed' in result.stderr, result.stderr
    assert (app / 'Contents' / 'Resources' / 'new').exists(), 'previous bundle must be restored'
    assert not (app / 'Contents' / 'Resources' / 'bad').exists()
    assert not bad.exists() and not any(bad_backup.iterdir()), 'failed bundle is removed'

    # First install has nothing to roll back to.
    first = root / '.first.app'
    first_app = root / 'First.app'
    make_app(first, 'com.example.first', '1', 'first')
    first_backup = Path(temporary) / 'first-backup'
    first_backup.mkdir()
    result = run(first_app, first, first_backup)
    assert result.returncode == 0, result.stderr
    assert (first_app / 'Contents' / 'Resources' / 'first').exists()

print('install-week check passed: atomic swap, same-build rejection, failed verification rollback, first install')
