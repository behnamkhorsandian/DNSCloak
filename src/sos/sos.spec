# SOS Binary Build Configuration
# ================================
# PyInstaller spec file for building standalone SOS executables

# -*- mode: python ; coding: utf-8 -*-
import os
import platform
from pathlib import Path

# Get the spec file directory and project root
SPEC_DIR = os.path.dirname(os.path.abspath(SPECPATH)) if 'SPECPATH' in dir() else os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = str(Path(SPEC_DIR).parent.parent)

# Allow CI to override platform detection via TARGET_PLATFORM env var
# Format: os-arch (e.g., linux-amd64, darwin-arm64, windows-amd64)
target_platform = os.environ.get('TARGET_PLATFORM', '')

if target_platform:
    # CI build with explicit target
    parts = target_platform.split('-')
    system = parts[0]
    arch = parts[1] if len(parts) > 1 else 'amd64'
else:
    # Local build - detect from host
    system = platform.system().lower()
    machine = platform.machine().lower()
    if 'arm' in machine or 'aarch64' in machine:
        arch = 'arm64'
    else:
        arch = 'amd64'

if system == 'darwin':
    dnstt_binary = f'bin/dnstt-client-darwin-{arch}'
    output_name = f'sos-darwin-{arch}'
elif system == 'linux':
    dnstt_binary = f'bin/dnstt-client-linux-{arch}'
    output_name = f'sos-linux-{arch}'
elif system == 'windows':
    dnstt_binary = 'bin/dnstt-client-windows-amd64.exe'
    output_name = 'sos-windows-amd64'
else:
    raise RuntimeError(f"Unsupported platform: {system}")

a = Analysis(
    ['src/sos/main.py'],
    pathex=[],
    binaries=[(dnstt_binary, 'bin')],
    datas=[
        ('src/sos/app.py', 'sos'),
        ('src/sos/room.py', 'sos'),
        ('src/sos/transport.py', 'sos'),
        ('src/sos/crypto.py', 'sos'),
        ('src/sos/__init__.py', 'sos'),
    ],
    hiddenimports=[
        'textual',
        'textual.app',
        'textual.screen',
        'textual.widgets',
        'textual.containers',
        'nacl',
        'nacl.secret',
        'nacl.utils',
        'httpx',
        'argon2',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name=output_name,
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
