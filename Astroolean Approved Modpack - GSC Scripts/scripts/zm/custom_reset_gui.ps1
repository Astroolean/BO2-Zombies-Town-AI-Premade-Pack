<#
══════════════════════════════════════════════════════════════════════════════
  ZM MOD SUITE — FULL MODPACK RESET (ASCII Console UI)
  Created by: Astroolean
  File: custom_reset_gui.ps1

  What this script does
  - Finds the Plutonium BO2 Zombies player config folder:
      %LOCALAPPDATA%\Plutonium\storage\t6\players
  - Creates a timestamped backup of each target config file before editing it.
  - Removes ONLY lines that set custom mod DVARs that match the prefix list below.
    (It matches both "set" and "seta" lines.)
  - Runs a final verification pass to confirm no matching DVAR lines remain.

  Target files (default)
  - config.cfg
  - plutonium_zm.cfg

  Backup behavior
  - Backups are created next to the original file as:
      <file>.bak_yyyyMMdd_HHmmss

  Safety notes
  - Close BO2 / Plutonium before running this reset.
  - This does not delete your config files.
  - This does not touch unrelated settings (only matching "set/seta <prefix...>" lines).

  UI speed (readability)
  - Change $UiSpeedMultiplier to control how slowly the UI prints:
      1.0 = normal speed
      2.0 = slower
      3.0+ = very slow

  Customizing prefixes
  - Add or remove items in $dvarPrefixes to control what gets wiped.

══════════════════════════════════════════════════════════════════════════════
#>

$ErrorActionPreference = 'Stop'

# Maximize console window (best-effort)
try {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@ | Out-Null
    $hWnd = [Win32.NativeMethods]::GetConsoleWindow()
    if ($hWnd -ne [IntPtr]::Zero) { [Win32.NativeMethods]::ShowWindowAsync($hWnd, 3) | Out-Null } # 3 = SW_MAXIMIZE
} catch { }

# ---------- SETTINGS ----------
# Where Plutonium stores BO2 player configs on Windows.
# NOTE: This uses LOCALAPPDATA so it follows the current Windows user profile.
# Folder that contains the config files we will scan / backup / clean.
$playersDir = Join-Path $env:LOCALAPPDATA 'Plutonium\storage\t6\players'
# The config files to clean. Add more paths here if you store settings elsewhere.
$targets = @(
    (Join-Path $playersDir 'config.cfg'),
    (Join-Path $playersDir 'plutonium_zm.cfg')
)

# Prefix list for any DVARs you want wiped.
# Only lines starting with: set/seta <prefix...> are removed.
$dvarPrefixes = @(
    'ct_',
    'cs_',
    'ds_',
    'sr_',
    'rl_',
    'sc_',
    'wb_',
    'lava_',
    'force_weather_',
    'perma_snow',
    'weather',
    'pap_price'
)

# Friendly names used only for the on-screen breakdown report.
$modNames = @{
    'ct_'            = 'Counter / Career Stats'
    'cs_'            = 'Round Summary'
    'ds_'            = 'Deadshot Overhaul'
    'sr_'            = 'Self-Revive'
    'rl_'            = 'Reload System'
    'sc_'            = 'Speed Controller'
    'wb_'            = 'Weapon Balance'
    'lava_'          = 'Lava Protection'
    'force_weather_' = 'Weather Control'
    'perma_snow'     = 'Origins Snow'
    'weather'        = 'Weather State'
    'pap_price'      = 'Pack-a-Punch Price'
}

# Build one regular expression that matches lines like:
#   set  ct_example 123
#   seta sr_someFlag 1
# Anything that does NOT match stays untouched.
$prefixJoined = ($dvarPrefixes | ForEach-Object { [regex]::Escape($_) }) -join '|'
$lineRegex = '^\s*(?:seta|set)\s+(?:' + $prefixJoined + ')[A-Za-z0-9_]*\s+'

# ---------- UI ----------
# Everything below here is just console formatting / printing helpers.
$Indent = '  '
$UiWidth = 88
try {
    $w = $Host.UI.RawUI.WindowSize.Width
    if ($w -ge 70) { $UiWidth = [Math]::Min(110, [Math]::Max(70, $w - 6)) }
} catch { }

# UI speed control (how slow the on-screen output prints)
#  1.0 = normal, 2.0 = ~2x slower, 3.0+ = very slow
[double]$UiSpeedMultiplier = 2.5

function _UiSleep([int]$ms) {
    # Centralized, safe sleep used for UI pacing (scaled by $UiSpeedMultiplier).
    if ($ms -le 0) { return }
    if ($UiSpeedMultiplier -le 0) { return }
    $scaled = [int][Math]::Round(($ms * $UiSpeedMultiplier), 0, [MidpointRounding]::AwayFromZero)
    if ($scaled -le 0) { return }
    _UiSleep $scaled
}

function _ClampInt([int]$v, [int]$min, [int]$max) {
    if ($v -lt $min) { return $min }
    if ($v -gt $max) { return $max }
    return $v
}

function _PadRight([string]$s, [int]$w) {
    if ($null -eq $s) { $s = '' }
    if ($s.Length -ge $w) { return $s.Substring(0, $w) }
    return $s + (' ' * ($w - $s.Length))
}

function _Center([string]$s, [int]$w) {
    if ($null -eq $s) { $s = '' }
    if ($s.Length -ge $w) { return $s.Substring(0, $w) }
    $pad = $w - $s.Length
    $left = [int][Math]::Floor($pad / 2)
    $right = $pad - $left
    return (' ' * $left) + $s + (' ' * $right)
}

function _Wrap([string]$s, [int]$w) {
    $out = New-Object 'System.Collections.Generic.List[string]'
    if ([string]::IsNullOrEmpty($s)) { $out.Add(''); return $out }

    $words = $s -split '\s+'
    $line = ''
    foreach ($word in $words) {
        if ($line.Length -eq 0) {
            $line = $word
        } elseif (($line.Length + 1 + $word.Length) -le $w) {
            $line = $line + ' ' + $word
        } else {
            $out.Add($line)
            $line = $word
        }
    }
    if ($line.Length -gt 0) { $out.Add($line) }
    return $out
}

function _Rule([char]$ch = '=', [ConsoleColor]$color = 'DarkCyan') {
    Write-Host ($Indent + ($ch.ToString() * $UiWidth)) -ForegroundColor $color
}

function _TitleBlock([string]$title, [string[]]$sub) {
    _Rule '=' 'Cyan'
    Write-Host ($Indent + (_Center $title $UiWidth)) -ForegroundColor White
    _Rule '-' 'DarkCyan'
    foreach ($ln in $sub) {
        foreach ($wln in (_Wrap $ln $UiWidth)) {
            Write-Host ($Indent + (_PadRight $wln $UiWidth)) -ForegroundColor DarkGray
        }
    }
    _Rule '=' 'Cyan'
    Write-Host ''
}

function _WarnBlock([string[]]$lines) {
    _Rule '!' 'Red'
    foreach ($ln in $lines) {
        foreach ($wln in (_Wrap $ln $UiWidth)) {
            Write-Host ($Indent + (_PadRight $wln $UiWidth)) -ForegroundColor Red
        }
    }
    _Rule '!' 'Red'
    Write-Host ''
}

function _Section([string]$name, [int]$idx, [int]$total) {
    Write-Host ''
    $hdr = ('[{0}/{1}] {2}' -f $idx, $total, $name)
    Write-Host ($Indent + $hdr) -ForegroundColor Cyan
    _Rule '-' 'DarkCyan'
}

function _SlowLine([string]$text, [ConsoleColor]$color = 'Cyan', [int]$charMs = 6) {
    foreach ($ch in $text.ToCharArray()) {
        Write-Host $ch -NoNewline -ForegroundColor $color
        _UiSleep $charMs
    }
    Write-Host ''
}

function _StatusRow([string]$left, [string]$tag, [ConsoleColor]$tagColor, [string]$right = '') {
    $leftW = 24
    $tagW  = 8
    $rightW = [Math]::Max(0, $UiWidth - ($leftW + 1 + $tagW + 1))
    $l = _PadRight $left $leftW
    $t = _PadRight $tag $tagW
    $r = _PadRight $right $rightW
    Write-Host ($Indent + $l + ' ') -NoNewline -ForegroundColor DarkGray
    Write-Host ($t + ' ') -NoNewline -ForegroundColor $tagColor
    Write-Host $r -ForegroundColor DarkGray
}

function _Progress([int]$current, [int]$total, [string]$label) {
    $total = [Math]::Max(1, $total)
    $pct = [int][Math]::Round(($current / [double]$total) * 100, 0, [MidpointRounding]::AwayFromZero)
    if ($current -ge $total) { $pct = 100 }
    $barW = 40
    $filled = [int][Math]::Round(($barW * $pct) / 100.0, 0, [MidpointRounding]::AwayFromZero)
    $filled = _ClampInt $filled 0 $barW
    if ($pct -eq 100) { $filled = $barW }
    $empty = $barW - $filled
    $bar = '[' + ('#' * $filled) + ('-' * $empty) + ']'
    $line = ('{0}  {1,3}%  ({2}/{3})' -f $bar, $pct, $current, $total)

    Write-Host ($Indent + 'Progress: ') -NoNewline -ForegroundColor DarkGray
    Write-Host $line -ForegroundColor DarkGray
    if (-not [string]::IsNullOrEmpty($label)) {
        Write-Host ($Indent + 'Current : ' + $label) -ForegroundColor DarkGray
    }
}

function _Divider() {
    Write-Host ($Indent + (' ' * $UiWidth)) | Out-Null
}

# ---------- START ----------
# Main entry point. From here the script prints UI, confirms, then runs:
#   1) Scan   2) Backup + Clean   3) Verify
Clear-Host

_TitleBlock 'ZM MOD SUITE - FULL RESET' @(
    'Resets custom mod settings / stats back to defaults.',
    'Creates timestamped backups before cleaning.',
    'Runs a final verification pass to confirm configs are clean.'
)

_SlowLine ($Indent + 'Initializing reset sequence...') Cyan 8
_UiSleep 150
Write-Host ''

# Target mods (2 columns)
Write-Host ($Indent + 'Target mods:') -ForegroundColor Yellow
$modsSorted = ($modNames.GetEnumerator() | Sort-Object Value | ForEach-Object { $_.Value })
$colW = [int][Math]::Floor(($UiWidth - 4) / 2)
for ($i = 0; $i -lt $modsSorted.Count; $i += 2) {
    $a = _PadRight $modsSorted[$i] $colW
    $b = ''
    if (($i + 1) -lt $modsSorted.Count) { $b = $modsSorted[$i + 1] }
    $b = _PadRight $b $colW
    Write-Host ($Indent + '  - ' + $a + '  - ' + $b) -ForegroundColor DarkGray
    _UiSleep 20
}

Write-Host ''
Write-Host ($Indent + 'Config directory:') -ForegroundColor Yellow
foreach ($ln in (_Wrap $playersDir $UiWidth)) {
    Write-Host ($Indent + '  ' + $ln) -ForegroundColor DarkGray
}
Write-Host ''

_WarnBlock @(
    'WARNING: Close BO2 / Plutonium before resetting.',
    'All career stats and mod settings will be wiped.'
)

$confirm = Read-Host ($Indent + 'Type YES to confirm full modpack reset')
if ($confirm -ne 'YES') {
    Write-Host ''
    Write-Host ($Indent + 'Reset cancelled.') -ForegroundColor Yellow
    Write-Host ''
    Read-Host ($Indent + 'Press Enter to exit') | Out-Null
    exit
}

Write-Host ''
Write-Host ($Indent + 'Confirmed. Starting reset...') -ForegroundColor Green
_UiSleep 200

$totalPhases = 3
$totalRemoved = 0
$totalFilesChanged = 0

# Track removals per file for summary (optional)
$removedByFile = @{}

# ---------- PHASE 1: SCAN ----------
_Section 'SCAN CONFIGS' 1 $totalPhases

foreach ($cfg in $targets) {
    $cfgName = Split-Path $cfg -Leaf

    if (!(Test-Path $cfg)) {
        _StatusRow $cfgName '[SKIP]' Yellow 'File not found'
        continue
    }

    $lines = [System.IO.File]::ReadAllLines($cfg)
    $matchCount = 0
    foreach ($line in $lines) { if ($line -match $lineRegex) { $matchCount++ } }

    if ($matchCount -gt 0) {
        _StatusRow $cfgName '[FOUND]' Yellow ("{0} mod dvars" -f $matchCount)
    } else {
        _StatusRow $cfgName '[CLEAN]' DarkGreen 'No mod dvars'
    }
    _UiSleep 120
}

# ---------- PHASE 2: BACKUP + CLEAN ----------
_Section 'BACKUP + CLEAN' 2 $totalPhases

$fileIndex = 0
$totalFiles = $targets.Count

foreach ($cfg in $targets) {
    $fileIndex++
    $cfgName = Split-Path $cfg -Leaf

    if (!(Test-Path $cfg)) { continue }

    _Progress ($fileIndex - 1) $totalFiles ("Backup + clean: " + $cfgName)
    _UiSleep 80

    # Backup
    $stamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup = "$cfg.bak_$stamp"
    Copy-Item $cfg $backup -Force
    _StatusRow $cfgName '[BACKUP]' Green (Split-Path $backup -Leaf)

    # Clean
    $lines   = [System.IO.File]::ReadAllLines($cfg)
    $kept    = New-Object 'System.Collections.Generic.List[string]'
    $removed = New-Object 'System.Collections.Generic.List[string]'

    foreach ($line in $lines) {
        if ($line -match $lineRegex) { $removed.Add($line) } else { $kept.Add($line) }
    }

    if ($removed.Count -gt 0) {
        [System.IO.File]::WriteAllLines($cfg, $kept, [System.Text.Encoding]::ASCII)
        $totalRemoved += $removed.Count
        $totalFilesChanged++
        $removedByFile[$cfgName] = $removed.Count

        _StatusRow $cfgName '[CLEAN]' Green ("Removed {0}" -f $removed.Count)

        # Per-mod breakdown (compact, sorted)
        $perMod = @{}
        foreach ($line in $removed) {
            $dvar = ''
            if ($line -match '(?:seta|set)\s+(\S+)') { $dvar = $Matches[1] }

            $matched = $false
            foreach ($pfx in ($dvarPrefixes | Sort-Object { $_.Length } -Descending)) {
                if ($dvar.StartsWith($pfx)) {
                    $label = $modNames[$pfx]
                    if (-not $perMod.ContainsKey($label)) { $perMod[$label] = 0 }
                    $perMod[$label]++
                    $matched = $true
                    break
                }
            }
            if (-not $matched) {
                if (-not $perMod.ContainsKey('Other')) { $perMod['Other'] = 0 }
                $perMod['Other']++
            }
        }

        foreach ($entry in ($perMod.GetEnumerator() | Sort-Object Value -Descending)) {
            $nm = _PadRight $entry.Key 30
            $ct = ('{0,4}' -f $entry.Value)
            Write-Host ($Indent + '  - ' + $nm + $ct) -ForegroundColor DarkGray
            _UiSleep 25
        }
    } else {
        $removedByFile[$cfgName] = 0
        _StatusRow $cfgName '[CLEAN]' DarkGreen 'No mod dvars'
    }

    Write-Host ''
    _Progress $fileIndex $totalFiles 'Overall files processed'
    Write-Host ''
    _UiSleep 150
}

# ---------- PHASE 3: VERIFY ----------
_Section 'VERIFY' 3 $totalPhases

foreach ($cfg in $targets) {
    $cfgName = Split-Path $cfg -Leaf
    if (!(Test-Path $cfg)) { continue }

    $lines = [System.IO.File]::ReadAllLines($cfg)
    $remaining = 0
    foreach ($line in $lines) { if ($line -match $lineRegex) { $remaining++ } }

    if ($remaining -eq 0) {
        _StatusRow $cfgName '[PASS]' Green 'Verified clean'
    } else {
        _StatusRow $cfgName '[FAIL]' Red ("Still has {0} mod dvars" -f $remaining)
    }
    _UiSleep 120
}

# ---------- SUMMARY ----------
Write-Host ''
_Rule '=' 'Green'
Write-Host ($Indent + (_Center 'RESET COMPLETE' $UiWidth)) -ForegroundColor White
_Rule '-' 'DarkGreen'

Write-Host ($Indent + ('Files modified      : {0}' -f $totalFilesChanged)) -ForegroundColor DarkGray
Write-Host ($Indent + ('Total dvars removed : {0}' -f $totalRemoved)) -ForegroundColor DarkGray

Write-Host ''
Write-Host ($Indent + 'Next: Start a fresh private match. Scripts will recreate defaults automatically.') -ForegroundColor DarkGray
_Rule '=' 'Green'

Write-Host ''
Read-Host ($Indent + 'Press Enter to exit') | Out-Null
