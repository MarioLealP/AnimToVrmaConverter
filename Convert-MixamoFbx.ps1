<#
.SYNOPSIS
    Mixamo .fbx -> .vrma. Much simpler than Generate-Animation.ps1's T2A
    pipeline - Mixamo FBX is already a real Humanoid-rigged animation, no
    laptop/SSH/GPU/SMPLify/Blender step needed at all.

.DESCRIPTION
    Reuses the exact same Unity-side machinery Generate-Animation.ps1 built
    for the T2A pipeline, since the problem past that point is identical
    either way - get a real standalone Humanoid .anim file, then hand it to
    the existing Convert-AnimToVrma.ps1:
      1. Copy the Mixamo .fbx into the Unity project's Assets folder.
      2. FbxHumanoidSetup.cs: set the rig to Humanoid, let Unity's own
         automatic bone-mapper build the Avatar (works on Mixamo's bone
         names same as it worked on Blender's BVH-import bone names).
      3. BvhBridgeExtractor.cs: extract the embedded AnimationClip
         sub-asset to a standalone .anim file - VrmaCliConverter only
         loads a real standalone .anim, not a sub-asset.
      4. Convert-AnimToVrma.ps1 -> the final .vrma.

.PARAMETER FbxPath
    Path to the downloaded Mixamo .fbx file.

.PARAMETER OutputVrma
    Where to write the final .vrma file.

.EXAMPLE
    .\Convert-MixamoFbx.ps1 -FbxPath "C:\Users\lealm\Downloads\Walking.fbx" -OutputVrma "F:\workspace\Projects\felt-character-assets\felt-godot-overlay\animations\library\idle\walk.vrma"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$FbxPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputVrma,

    [string]$UnityProject = "F:\workspace\Projects\AnimToVrmaConverter\My project",
    [string]$WorkDir = "F:\workspace\Projects\AnimToVrmaConverter\sample_output"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $FbxPath)) { throw "-FbxPath $FbxPath does not exist." }

$stamp = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$assetsFbx = Join-Path $UnityProject "Assets\GeneratedAnimations\mixamo_$stamp.fbx"
$unityFbxRelPath = "Assets/GeneratedAnimations/mixamo_$stamp.fbx"
$unityAnimRelPath = "Assets/GeneratedAnimations/mixamo_$stamp.anim"
$UnityExe = "C:\Program Files\Unity\Hub\Editor\2022.3.62f3\Editor\Unity.exe"

Write-Host "[1/3] Importing FBX into Unity as Humanoid" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $assetsFbx) | Out-Null
Copy-Item $FbxPath $assetsFbx -Force

$setupLog = Join-Path $WorkDir "mixamo_$stamp`_setup.log"
$p1 = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode","-quit","-projectPath","`"$UnityProject`"","-executeMethod","FbxHumanoidSetup.SetupFromCommandLine","-fbxPath","$unityFbxRelPath","-logFile","`"$setupLog`"" -Wait -NoNewWindow -PassThru
$setupOut = (Get-Content $setupLog | Select-String "FbxHumanoidSetup:") -join "`n"
Write-Host "  $setupOut"
if ($p1.ExitCode -ne 0 -or ($setupOut -notmatch "isHuman=True")) {
    throw "Unity Humanoid auto-mapping failed - see $setupLog. Mixamo's bone names usually auto-map cleanly; if this fails, the FBX may need manual bone mapping in the Unity Editor once, or isn't a Humanoid-compatible rig."
}

Write-Host "[2/3] Extracting the Humanoid AnimationClip" -ForegroundColor Cyan
$extractLog = Join-Path $WorkDir "mixamo_$stamp`_extract.log"
$p2 = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode","-quit","-projectPath","`"$UnityProject`"","-executeMethod","BvhBridgeExtractor.ExtractFromCommandLine","-prefabPath","$unityFbxRelPath","-outPath","$unityAnimRelPath","-logFile","`"$extractLog`"" -Wait -NoNewWindow -PassThru
$extractOut = (Get-Content $extractLog | Select-String "BvhBridgeExtractor:") -join "`n"
Write-Host "  $extractOut"
if ($p2.ExitCode -ne 0 -or ($extractOut -notmatch "isHumanMotion=True")) {
    throw "AnimationClip extraction failed or clip is not Humanoid - see $extractLog"
}

Write-Host "[3/3] Converting to .vrma" -ForegroundColor Cyan
$animAbsPath = Join-Path $UnityProject "Assets\GeneratedAnimations\mixamo_$stamp.anim"
& (Join-Path $PSScriptRoot "Convert-AnimToVrma.ps1") -InputPath $animAbsPath -OutputPath $OutputVrma

if (Test-Path $OutputVrma) {
    Write-Host "`nDone: $OutputVrma" -ForegroundColor Green
} else {
    throw "Final .vrma was not produced."
}
