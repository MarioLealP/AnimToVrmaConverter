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
    Mutually exclusive with -BvhPath.

.PARAMETER BvhPath
    Skip stages 1-2 (SSH generation) and start from an already-generated .bvh file -
    used by felt-t2a-studio, which generates the .bvh itself via the persistent
    inference server (see inference_server.py on the laptop) so the fast preview
    and the eventual conversion share the exact same generated motion, not two
    independent (stochastic) samples. Mutually exclusive with -Prompt.

.PARAMETER OutputVrma
    Where to write the final .vrma file.

.EXAMPLE
    .\Generate-Animation.ps1 -Prompt "a person does a backflip" -OutputVrma "F:\workspace\Projects\felt-character-assets\felt-godot-overlay\animations\library\reaction\test\backflip.vrma"

.EXAMPLE
    .\Generate-Animation.ps1 -BvhPath "F:\path\to\already_generated.bvh" -OutputVrma "F:\path\to\output.vrma"
#>
param(
    [string]$Prompt,

    [string]$BvhPath,

    [Parameter(Mandatory=$true)]
    [string]$OutputVrma,

    [string]$LaptopHost = "clockmost-nitro5",
    [string]$LaptopWorkDir = "~/felt-t2a-spike",
    [string]$UnityProject = "F:\workspace\Projects\AnimToVrmaConverter\My project",
    [string]$WorkDir = "F:\workspace\Projects\AnimToVrmaConverter\sample_output",
    [string]$BlenderExe = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Prompt) -eq [string]::IsNullOrWhiteSpace($BvhPath)) {
    throw "Provide exactly one of -Prompt or -BvhPath, not both/neither."
}

$stamp = [System.Guid]::NewGuid().ToString().Substring(0, 8)
$bvhLocal = if ($BvhPath) { $BvhPath } else { Join-Path $WorkDir "gen_$stamp.bvh" }
$fbxLocal = Join-Path $WorkDir "gen_$stamp.fbx"

# Per-stage timing - the pipeline chains a remote GPU job, a local headless
# Blender process, and two separate headless Unity launches, each with its
# own startup/compile overhead, so "how long does one generation actually
# take" isn't obvious from any single piece. Logged to a running metrics
# file (below) as well as printed, so this is a real trend to look at over
# multiple runs, not just a one-off number.
$timings = [ordered]@{}
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()
function Time-Stage([string]$Name, [scriptblock]$Body) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Body
    $sw.Stop()
    $script:timings[$Name] = [math]::Round($sw.Elapsed.TotalSeconds, 2)
}

if ($BvhPath) {
    Write-Host "[1-2/6] Using pre-generated BVH: $BvhPath (skipping SSH generation)" -ForegroundColor Cyan
    if (-not (Test-Path $bvhLocal)) { throw "-BvhPath $BvhPath does not exist." }
    $timings["1_generate_motion_ssh"] = 0
    $timings["2_scp_bvh"] = 0
} else {
    Time-Stage "1_generate_motion_ssh" {
        Write-Host "[1/6] Generating motion on $LaptopHost for: `"$Prompt`"" -ForegroundColor Cyan
        $script:remoteBvh = "/tmp/gen_$stamp.bvh"
        $sshResult = ssh $LaptopHost "cd $LaptopWorkDir && uv run python generate_bvh.py --prompt '$($Prompt -replace "'", "''")' --out $script:remoteBvh 2>&1"
        if ($LASTEXITCODE -ne 0 -or -not ($sshResult -match "BVH saved")) {
            Write-Host $sshResult
            throw "Motion generation failed on $LaptopHost."
        }
        Write-Host "  done." -ForegroundColor Green
    }

    Time-Stage "2_scp_bvh" {
        Write-Host "[2/6] Pulling .bvh to this desktop" -ForegroundColor Cyan
        scp "${LaptopHost}:${remoteBvh}" $bvhLocal
        if (-not (Test-Path $bvhLocal)) { throw "scp of $remoteBvh failed." }
    }
}

Time-Stage "3_blender_bvh_to_fbx" {
    Write-Host "[3/6] Converting BVH -> FBX via headless Blender" -ForegroundColor Cyan
    & $BlenderExe --background --python (Join-Path $PSScriptRoot "bvh_to_fbx.py") -- $bvhLocal $fbxLocal 2>&1 | Out-Null
    if (-not (Test-Path $fbxLocal)) { throw "Blender BVH->FBX conversion failed." }
}

$assetsFbx = Join-Path $UnityProject "Assets\GeneratedAnimations\gen_$stamp.fbx"
$unityFbxRelPath = "Assets/GeneratedAnimations/gen_$stamp.fbx"
$UnityExe = "C:\Program Files\Unity\Hub\Editor\2022.3.62f3\Editor\Unity.exe"

Time-Stage "4_unity_humanoid_setup" {
    Write-Host "[4/6] Importing FBX into Unity as Humanoid" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Split-Path $assetsFbx) | Out-Null
    Copy-Item $fbxLocal $assetsFbx -Force

    $setupLog = Join-Path $WorkDir "gen_$stamp`_setup.log"
    $p1 = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode","-quit","-projectPath","`"$UnityProject`"","-executeMethod","FbxHumanoidSetup.SetupFromCommandLine","-fbxPath","$unityFbxRelPath","-logFile","`"$setupLog`"" -Wait -NoNewWindow -PassThru
    $setupOut = (Get-Content $setupLog | Select-String "FbxHumanoidSetup:") -join "`n"
    Write-Host "  $setupOut"
    if ($p1.ExitCode -ne 0 -or ($setupOut -notmatch "isHuman=True")) {
        throw "Unity Humanoid auto-mapping failed - see $setupLog"
    }
}

$unityAnimRelPath = "Assets/GeneratedAnimations/gen_$stamp.anim"

Time-Stage "5_unity_extract_clip" {
    Write-Host "[5/6] Extracting the Humanoid AnimationClip" -ForegroundColor Cyan
    $extractLog = Join-Path $WorkDir "gen_$stamp`_extract.log"
    $p2 = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode","-quit","-projectPath","`"$UnityProject`"","-executeMethod","BvhBridgeExtractor.ExtractFromCommandLine","-prefabPath","$unityFbxRelPath","-outPath","$unityAnimRelPath","-logFile","`"$extractLog`"" -Wait -NoNewWindow -PassThru
    $extractOut = (Get-Content $extractLog | Select-String "BvhBridgeExtractor:") -join "`n"
    Write-Host "  $extractOut"
    if ($p2.ExitCode -ne 0 -or ($extractOut -notmatch "isHumanMotion=True")) {
        throw "AnimationClip extraction failed or clip is not Humanoid - see $extractLog"
    }
}

Time-Stage "6_convert_to_vrma" {
    Write-Host "[6/6] Converting to .vrma" -ForegroundColor Cyan
    $animAbsPath = Join-Path $UnityProject "Assets\GeneratedAnimations\gen_$stamp.anim"
    & (Join-Path $PSScriptRoot "Convert-AnimToVrma.ps1") -InputPath $animAbsPath -OutputPath $OutputVrma
}

$totalSw.Stop()
$totalSeconds = [math]::Round($totalSw.Elapsed.TotalSeconds, 2)

Write-Host "`n--- Timing ---" -ForegroundColor Yellow
foreach ($k in $timings.Keys) {
    Write-Host ("  {0,-28} {1,6}s" -f $k, $timings[$k])
}
Write-Host ("  {0,-28} {1,6}s" -f "TOTAL", $totalSeconds) -ForegroundColor Yellow

$metricsLog = Join-Path $WorkDir "pipeline_timings.jsonl"
$record = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    prompt    = if ($Prompt) { $Prompt } else { "(pre-generated bvh: $BvhPath)" }
    stamp     = $stamp
    success   = (Test-Path $OutputVrma)
    timings   = $timings
    total_seconds = $totalSeconds
}
($record | ConvertTo-Json -Compress) | Add-Content -Path $metricsLog

if (Test-Path $OutputVrma) {
    Write-Host "`nDone: $OutputVrma" -ForegroundColor Green
} else {
    throw "Final .vrma was not produced."
}
