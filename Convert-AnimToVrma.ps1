param (
    [Parameter(Mandatory=$true, HelpMessage="Path to the source .anim or .unitypackage file")]
    [string]$InputPath,

    [Parameter(Mandatory=$false, HelpMessage="Optional specific output path for the .vrma file")]
    [string]$OutputPath,

    [Parameter(Mandatory=$false)]
    [string]$UnityProject = "E:\Felt\AnimToVrmaConverter\My project",

    [Parameter(Mandatory=$false)]
    [string]$UnityExe = "C:\Program Files\Unity\Hub\Editor\2022.3.62f3\Editor\Unity.exe"
)

$InputAbs = (Resolve-Path $InputPath).Path
$OutputDir = [System.IO.Path]::GetDirectoryName($InputAbs)
$Ext = [System.IO.Path]::GetExtension($InputAbs).ToLower()

function Convert-AnimFile {
    param([string]$AnimFile, [string]$OutFile)
    
    $LogFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($AnimFile), "unity_vrma_export_$([System.Guid]::NewGuid().ToString().Substring(0,5)).log")
    
    Write-Host "Starting headless Unity conversion..." -ForegroundColor Cyan
    Write-Host "Source: $AnimFile"
    Write-Host "Target: $OutFile"
    
    $process = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode", "-quit", "-projectPath", "`"$UnityProject`"", "-executeMethod", "VrmaCliConverter.ConvertFromCommandLine", "-animPath", "`"$AnimFile`"", "-outputPath", "`"$OutFile`"", "-logFile", "`"$LogFile`"" -Wait -NoNewWindow -PassThru
    
    if (Test-Path $OutFile) {
        Write-Host "Success: Generated $OutFile" -ForegroundColor Green
    } else {
        Write-Host "Failed to generate .vrma file. See log for details: $LogFile" -ForegroundColor Red
        Write-Host "Exit Code: $($process.ExitCode)"
    }
}

if ($Ext -eq ".anim") {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = [System.IO.Path]::ChangeExtension($InputAbs, ".vrma")
    }
    Convert-AnimFile -AnimFile $InputAbs -OutFile $OutputPath
}
elseif ($Ext -eq ".unitypackage") {
    Write-Host "UnityPackage detected. Analyzing project state before import..." -ForegroundColor Yellow
    
    $AssetsDir = Join-Path $UnityProject "Assets"
    
    $BeforeAnims = @()
    if (Test-Path $AssetsDir) {
        $BeforeAnims = (Get-ChildItem -Path $AssetsDir -Filter "*.anim" -Recurse).FullName
    }
    
    $LogFile = Join-Path $OutputDir "unity_import_pkg.log"
    Write-Host "Importing package into Unity..." -ForegroundColor Cyan
    $process = Start-Process -FilePath $UnityExe -ArgumentList "-batchmode", "-quit", "-projectPath", "`"$UnityProject`"", "-importPackage", "`"$InputAbs`"", "-logFile", "`"$LogFile`"" -Wait -NoNewWindow -PassThru
    
    if ($process.ExitCode -ne 0) {
        Write-Host "Failed to import .unitypackage. Exit code: $($process.ExitCode). See log: $LogFile" -ForegroundColor Red
        exit $process.ExitCode
    }
    
    $AfterAnims = (Get-ChildItem -Path $AssetsDir -Filter "*.anim" -Recurse).FullName
    $NewAnims = $AfterAnims | Where-Object { $BeforeAnims -notcontains $_ }
    
    if ($NewAnims.Count -eq 0) {
        Write-Host "No new .anim files were found inside the unitypackage!" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $($NewAnims.Count) new animation(s) in the package. Beginning batch conversion..." -ForegroundColor Green
    
    foreach ($anim in $NewAnims) {
        $FileName = [System.IO.Path]::GetFileNameWithoutExtension($anim)
        $OutPath = Join-Path $OutputDir "$FileName.vrma"
        Write-Host "`n--> Converting $FileName" -ForegroundColor Cyan
        Convert-AnimFile -AnimFile $anim -OutFile $OutPath
    }
    Write-Host "`nBatch conversion complete!" -ForegroundColor Green
}
else {
    Write-Host "Unsupported file type: $Ext" -ForegroundColor Red
    exit 1
}
