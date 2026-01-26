# SOS Binary Build Configuration
# ================================
# PyInstaller spec file for building standalone SOS executables

# -*- mode: python ; coding: utf-8 -*-
import platform

# Platform-specific DNSTT binary
system = platform.system().lower()
machine = platform.machine().lower()

if system == 'darwin':
    if 'arm' in machine or 'aarch64' in machine:
        dnstt_binary = 'bin/dnstt-client-darwin-arm64'
        output_name = 'sos-darwin-arm64'
    else:
        dnstt_binary = 'bin/dnstt-client-darwin-amd64'
        output_name = 'sos-darwin-amd64'
elif system == 'linux':
    if 'arm' in machine or 'aarch64' in machine:
        dnstt_binary = 'bin/dnstt-client-linux-arm64'
        output_name = 'sos-linux-arm64'
    else:
        dnstt_binary = 'bin/dnstt-client-linux-amd64'
        output_name = 'sos-linux-amd64'
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
