<#
.SYNOPSIS
    Deletes static pose files (not real animations) from a Mixamo download folder.

.DESCRIPTION
    Mixamo's catalog includes single-frame "pose" references alongside real
    animations - not useful content for Felt's reaction library, since
    they're static, not something that plays as a motion. Matches "pose"
    anywhere in the filename, case-insensitive.

    Safe to re-run repeatedly as more files download in (Mario, 2026-09-21:
    "still downloading").

.PARAMETER Path
    Folder to scan. Defaults to E:\Mixamo.

.PARAMETER WhatIf
    List what would be deleted without actually deleting anything.

.EXAMPLE
    .\Remove-MixamoPoses.ps1
.EXAMPLE
    .\Remove-MixamoPoses.ps1 -WhatIf
#>
param(
    [string]$Path = "E:\Mixamo",
    [switch]$WhatIf
)

$matches = Get-ChildItem -Path $Path -Filter "*.fbx" -File | Where-Object { $_.BaseName -match "(?i)pose" }

if ($matches.Count -eq 0) {
    Write-Host "No pose files found in $Path."
    exit 0
}

Write-Host "Found $($matches.Count) pose file(s):"
$matches | ForEach-Object { Write-Host "  $($_.Name)" }

if ($WhatIf) {
    Write-Host "`n-WhatIf set, nothing deleted."
} else {
    $matches | Remove-Item -Force
    Write-Host "`nDeleted $($matches.Count) file(s)."
}
