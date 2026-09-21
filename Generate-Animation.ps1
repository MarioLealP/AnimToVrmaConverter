<#
.SYNOPSIS
    Full text -> .vrma pipeline: T2M-GPT (on the Nitro5 laptop) -> BVH -> Blender FBX ->
    Unity Humanoid retarget -> VrmaCliConverter.

.DESCRIPTION
    Consolidates the manual chain built and verified working 2026-09-21:
      1. SSH to clockmost-nitro5, run T2M-GPT generation + SMPLify fitting + smpl2bvh
         (generate_bvh.py in ~/felt-t2a-spike) -> .bvh
      2. scp the .bvh back to this desktop
      3. Blender headless: import BVH, export FBX (bvh_to_fbx.py) - UniHumanoid's own
         BVH importer only produces a LEGACY clip (Animation.legacy = true in its own
         source), which can never satisfy VrmaCliConverter's isHumanMotion check, so
         BVH->FBX->Unity's native Humanoid retargeting is the real bridge, not a
         detour. Two real bugs were found and fixed getting this step right:
           - the BVH importer needs update_scene_fps=True or the bake runs at the
             wrong fps entirely
           - FBX export bakes the SCENE's frame range, not the imported action's own
             range, so scene.frame_start/frame_end must be set to the action's real
             range first, or a 3-second clip gets padded out to Blender's ~12s
             default scene length
      4. Unity headless: set the FBX's rig to Humanoid, let Unity's own automatic
         bone-mapper build the Avatar (FbxHumanoidSetup.cs)
      5. Unity headless: extract the embedded AnimationClip sub-asset to a standalone
         .anim file (BvhBridgeExtractor.cs) - VrmaCliConverter only loads a real
         standalone .anim, not a sub-asset
      6. Convert-AnimToVrma.ps1 -> the final .vrma

    Also worth knowing: T2M-GPT's raw model output is in HumanML3D's NORMALIZED
    (mean/std z-scored) space - skipping the denormalization step before
    recover_from_ric causes the root joint position to jitter chaotically frame to
    frame (confirmed: thousands of units of "drift" in 60 frames for someone just
    standing and waving). generate_bvh.py on the laptop already does this correctly;
    if it's ever rewritten, keep it.

.PARAMETER Prompt
    The text prompt to generate a motion from, e.g. "a person waves with their right hand".

.PARAMETER OutputVrma
    Where to write the final .vrma file.

.EXAMPLE
    .\Generate-Animation.ps1 -Prompt "a person does a backflip" -OutputVrma "F:\workspace\Projects\felt-character-assets\felt-godot-overlay\animations\library\reaction\test\backflip.vrma"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Prompt,

    [Parameter(Mandatory=$true)]
    [string]$OutputVrma,

    [string]$LaptopHost = "clockmost-nitro5",
    [string]$LaptopWorkDir = "~/felt-t2a-spike",
    [string]$UnityProject = "F:\workspace\Projects\AnimToVrmaConverter\My project",
    [string]$WorkDir = "F:\workspace\Projects\AnimToVrmaConverter\sample_output",
    [string]$BlenderExe = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
)

$ErrorActionPreference = "Stop"
$stamp = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$bvhLocal = Join-Path $WorkDir "gen_$stamp.bvh"
$fbxLocal = Join-Path $WorkDir "gen_$stamp.fbx"

Write-Host "[1/6] Generating motion on $LaptopHost for: `"$Prompt`"" -ForegroundColor Cyan
$remoteBvh = "/tmp/gen_$stamp.bvh"
$sshResult = ssh $LaptopHost "cd $LaptopWorkDir && uv run python generate_bvh.py --prompt '$($Prompt -replace "'", "''")' --out $remoteBvh 2>&1"
if ($LASTEXITCODE -ne 0 -or -not ($sshResult -match "BVH saved")) {
    Write-Host $sshResult
    throw "Motion generation failed on $LaptopHost."
}
Write-Host "  done." -ForegroundColor Green

Write-Host "[2/6] Pulling .bvh to this desktop" -ForegroundColor Cyan
scp "${LaptopHost}:${remoteBvh}" $bvhLocal
if (-not (Test-Path $bvhLocal)) { throw "scp of $remoteBvh failed." }

Write-Host "[3/6] Converting BVH -> FBX via headless Blender" -ForegroundColor Cyan
& $BlenderExe --background --python (Join-Path $PSScriptRoot "bvh_to_fbx.py") -- $bvhLocal $fbxLocal 2>&1 | Out-Null
if (-not (Test-Path $fbxLocal)) { throw "Blender BVH->FBX conversion failed." }

Write-Host "[4/6] Importing FBX into Unity as Humanoid" -ForegroundColor Cyan
$assetsFbx = Join-Path $UnityProject "Assets\GeneratedAnimations\gen_$stamp.fbx"
New-Item -ItemType Directory -Force -Path (Split-Path $assetsFbx) | Out-Null
Copy-Item $fbxLocal $assetsFbx -Force
$unityFbxRelPath = "Assets/GeneratedAnimations/gen_$stamp.fbx"

$UnityExe = "C:\Program Files\Unity\Hub\Editor\2022.3.62f3\Editor\Unity.exe"
$setupLog = Join-Path $WorkDir "gen_$stamp`_setup.log"
$p1 = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode","-quit","-projectPath","`"$UnityProject`"","-executeMethod","FbxHumanoidSetup.SetupFromCommandLine","-fbxPath","$unityFbxRelPath","-logFile","`"$setupLog`"" -Wait -NoNewWindow -PassThru
$setupOut = (Get-Content $setupLog | Select-String "FbxHumanoidSetup:") -join "`n"
Write-Host "  $setupOut"
if ($p1.ExitCode -ne 0 -or ($setupOut -notmatch "isHuman=True")) {
    throw "Unity Humanoid auto-mapping failed - see $setupLog"
}

Write-Host "[5/6] Extracting the Humanoid AnimationClip" -ForegroundColor Cyan
$unityAnimRelPath = "Assets/GeneratedAnimations/gen_$stamp.anim"
$extractLog = Join-Path $WorkDir "gen_$stamp`_extract.log"
$p2 = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode","-quit","-projectPath","`"$UnityProject`"","-executeMethod","BvhBridgeExtractor.ExtractFromCommandLine","-prefabPath","$unityFbxRelPath","-outPath","$unityAnimRelPath","-logFile","`"$extractLog`"" -Wait -NoNewWindow -PassThru
$extractOut = (Get-Content $extractLog | Select-String "BvhBridgeExtractor:") -join "`n"
Write-Host "  $extractOut"
if ($p2.ExitCode -ne 0 -or ($extractOut -notmatch "isHumanMotion=True")) {
    throw "AnimationClip extraction failed or clip is not Humanoid - see $extractLog"
}

Write-Host "[6/6] Converting to .vrma" -ForegroundColor Cyan
$animAbsPath = Join-Path $UnityProject "Assets\GeneratedAnimations\gen_$stamp.anim"
& (Join-Path $PSScriptRoot "Convert-AnimToVrma.ps1") -InputPath $animAbsPath -OutputPath $OutputVrma

if (Test-Path $OutputVrma) {
    Write-Host "`nDone: $OutputVrma" -ForegroundColor Green
} else {
    throw "Final .vrma was not produced."
}
