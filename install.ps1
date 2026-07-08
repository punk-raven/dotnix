# install.ps1 - Windows entry point.
#
# Nix does not run natively on Windows, so this script ONLY bootstraps WSL2 and
# then hands off to install.sh inside the distro - the identical Linux path.
# All package logic lives in install.sh so Windows and Linux never diverge.
#
# Run from an ADMIN PowerShell:
#   irm https://raw.githubusercontent.com/allanjeo/dotfiles/main/install.ps1 | iex
#
# Requires Windows 10 21H2+ / Windows 11, virtualization enabled in BIOS/UEFI.
# WSLg (bundled with recent WSL) gives GUI apps a display; a headless install
# skips them.

$ErrorActionPreference = 'Stop'

$Distro    = if ($env:WSL_DISTRO_NAME2) { $env:WSL_DISTRO_NAME2 } else { 'Ubuntu' }
$RawScript = if ($env:DOTFILES_INSTALL_URL) { $env:DOTFILES_INSTALL_URL } `
             else { 'https://raw.githubusercontent.com/allanjeo/dotfiles/main/install.sh' }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (-not (Test-Admin)) {
  Write-Error "Run this from an elevated (Administrator) PowerShell - enabling WSL2 needs admin rights."
  exit 1
}

# 1. Ensure WSL2 + a distro. `wsl --install` enables the WSL and Virtual Machine
#    Platform features, installs the distro, and sets WSL2 as default in one go
#    on modern Windows. Idempotent: a no-op if WSL is already present.
Write-Host "Ensuring WSL2 and the $Distro distro are installed..."
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Write-Error "wsl.exe not found. Update Windows (10 21H2+/11), then re-run."
  exit 1
}

$installed = (wsl.exe --list --quiet) -join "`n"
if ($installed -notmatch [regex]::Escape($Distro)) {
  wsl.exe --install -d $Distro
  Write-Host ""
  Write-Host "WSL installed $Distro. If this is the first install, Windows may ask you"
  Write-Host "to REBOOT and to create a UNIX username/password on first launch."
  Write-Host "After that, re-run this script to continue into the Linux installer."
  # A fresh WSL install typically requires a reboot before the distro is usable.
  if ($installed -eq '') { exit 0 }
} else {
  Write-Host "$Distro already installed."
}

wsl.exe --set-default-version 2 | Out-Null
wsl.exe --set-default $Distro   | Out-Null

# 2. Hand off to the Linux installer INSIDE the distro. From here everything is
#    identical to a native Linux install.
Write-Host "Handing off to install.sh inside $Distro ..."
wsl.exe -d $Distro -- bash -lc "curl -fsSL $RawScript | sh"

Write-Host "Done. Launch '$Distro' from the Start menu to use your configured shell."
