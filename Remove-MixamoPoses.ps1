<#
.SYNOPSIS
    Deletes static single-frame pose files (not real animations) from a Mixamo download folder.

.DESCRIPTION
    Mixamo's catalog includes single-frame "pose" references alongside real
    animations - not useful content for Felt's reaction library, since
    they're static, not something that plays as a motion.

    Originally this matched "pose" in the filename, but that turned out to
    be wrong in practice (Mario, 2026-09-21): out of a real 63-file batch,
    52 were genuinely static single-frame poses and NONE of them had "pose"
    in the name - Mixamo names them descriptively instead ("Arms Down",
    "Legs Crossed, Arms Raised"), including some that sound like real
    motion but aren't ("Walking.fbx" is a static pose; the real animated
    walk is separately named "Female Normal Walk.fbx"). This version
    actually opens each file in headless Blender and checks the real
    animation frame range instead of guessing from the name - static poses
    have a frame_range span of ~1 frame or less; real animations don't.

    Safe to re-run repeatedly as more files download in.

.PARAMETER Path
    Folder to scan. Defaults to E:\Mixamo.

.PARAMETER BlenderExe
    Path to blender.exe.

.PARAMETER WhatIf
    List what would be deleted without actually deleting anything.

.EXAMPLE
    .\Remove-MixamoPoses.ps1
.EXAMPLE
    .\Remove-MixamoPoses.ps1 -WhatIf
#>
param(
    [string]$Path = "E:\Mixamo",
    [string]$BlenderExe = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
    [switch]$WhatIf
)

$fbxFiles = Get-ChildItem -Path $Path -Filter "*.fbx" -File
if ($fbxFiles.Count -eq 0) {
    Write-Host "No .fbx files found in $Path."
    exit 0
}

$scanScript = Join-Path $env:TEMP "scan_mixamo_poses.py"
@"
import bpy
import glob
import os

folder = r'$Path'
for path in sorted(glob.glob(os.path.join(folder, '*.fbx'))):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        bpy.ops.import_scene.fbx(filepath=path)
    except Exception as e:
        print(f'IMPORT_FAILED`t{os.path.basename(path)}`t{e}')
        continue
    actions = list(bpy.data.actions)
    if not actions:
        print(f'NO_ACTION`t{os.path.basename(path)}')
        continue
    fr = actions[0].frame_range
    span = fr[1] - fr[0]
    kind = 'STATIC_POSE' if span <= 1.0 else 'MOTION'
    print(f'{kind}`t{os.path.basename(path)}`t{span:.1f} frames')
"@ | Set-Content -Path $scanScript -Encoding utf8

Write-Host "Scanning $($fbxFiles.Count) file(s) with headless Blender (this takes a moment per file)..."
$output = & $BlenderExe --background --python $scanScript 2>&1 |
    Select-String -Pattern "^(STATIC_POSE|MOTION|NO_ACTION|IMPORT_FAILED)\t"

$toDelete = @()
foreach ($line in $output) {
    $parts = $line.ToString() -split "`t"
    $kind = $parts[0]
    $name = $parts[1]
    if ($kind -eq "STATIC_POSE") {
        $toDelete += $name
    } elseif ($kind -eq "IMPORT_FAILED" -or $kind -eq "NO_ACTION") {
        Write-Host "  SKIPPED (not a static pose, but couldn't classify): $name - $kind" -ForegroundColor Yellow
    }
}

if ($toDelete.Count -eq 0) {
    Write-Host "No static pose files found."
    exit 0
}

Write-Host "`nFound $($toDelete.Count) static pose file(s):"
$toDelete | ForEach-Object { Write-Host "  $_" }

if ($WhatIf) {
    Write-Host "`n-WhatIf set, nothing deleted."
} else {
    foreach ($name in $toDelete) {
        Remove-Item -Path (Join-Path $Path $name) -Force
    }
    Write-Host "`nDeleted $($toDelete.Count) file(s)."
}
