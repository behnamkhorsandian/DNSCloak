# Cloak for Windows

## Requirements
- Windows 10 (build 19041+) or Windows 11
- Windows Subsystem for Linux (WSL)

## Setup

1. **Install WSL** (if not already):
   Open PowerShell as Administrator and run:
   ```
   wsl --install
   ```
   Restart your computer after installation.

2. **Run Cloak**:
   Double-click `cloak.bat` or run from Command Prompt:
   ```
   cloak.bat
   cloak.bat help
   cloak.bat box
   cloak.bat mirrors
   ```

## How it works
`cloak.bat` launches the Cloak CLI inside WSL, where all bash scripts run natively. All features work the same as on Linux/macOS.

## Troubleshooting
- If WSL is not installed, you'll see instructions to run `wsl --install`
- If you get permission errors, right-click `cloak.bat` and select "Run as Administrator"
- For tmux support, install tmux inside WSL: `sudo apt install tmux`
