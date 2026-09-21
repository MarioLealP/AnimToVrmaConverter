<#
.SYNOPSIS
    Batch-converts a whole folder tree of Mixamo .fbx files to .vrma in ONE
    Unity session - built for hundreds of files, where Convert-MixamoFbx.ps1's
    per-file approach (two Unity relaunches per file) would take hours of
    pure startup overhead alone.

.DESCRIPTION
    Each subfolder path under -SourceRoot becomes the output tag, e.g.
    <SourceRoot>\emotion\happy\Cheering.fbx -> <OutputRoot>\emotion\happy\cheering.vrma.
    Resumable - already-converted files (output .vrma already exists) are
    skipped, so an interrupted run can just be re-run.

.PARAMETER SourceRoot
    Root of the sorted Mixamo folder tree (subfolders = tags).

.PARAMETER OutputRoot
    Where to write the resulting .vrma tree. Defaults to felt-overlay's
    actual curated library, so files land directly in place.

.EXAMPLE
    .\Convert-MixamoBatch.ps1 -SourceRoot "E:\Mixamo\sorted"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot,

    [string]$OutputRoot = "E:\Felt\felt-character-assets\felt-godot-overlay\animations\library",

    [string]$UnityProject = "E:\Felt\AnimToVrmaConverter\My project"
)

$ErrorActionPreference = "Stop"
$UnityExe = "C:\Program Files\Unity\Hub\Editor\2022.3.62f3\Editor\Unity.exe"
$logFile = "E:\Felt\AnimToVrmaConverter\sample_output\batch_mixamo_$([System.Guid]::NewGuid().ToString().Substring(0,8)).log"

Write-Host "Converting $SourceRoot -> $OutputRoot (one Unity session, may take a while for many files)..." -ForegroundColor Cyan

$p = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode","-quit","-projectPath","`"$UnityProject`"","-executeMethod","BatchMixamoConverter.RunFromCommandLine","-sourceRoot","`"$SourceRoot`"","-outputRoot","`"$OutputRoot`"","-logFile","`"$logFile`"" -Wait -NoNewWindow -PassThru

$summary = Get-Content $logFile | Select-String "BatchMixamoConverter:"
$summary | ForEach-Object { Write-Host "  $_" }

if ($p.ExitCode -ne 0) {
    throw "BatchMixamoConverter failed (exit $($p.ExitCode)) - see $logFile"
}
Write-Host "`nDone. Full log: $logFile" -ForegroundColor Green
