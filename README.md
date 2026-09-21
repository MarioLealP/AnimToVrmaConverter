# AnimToVrma Converter Pipeline

This folder contains a fully headless, drag-and-drop pipeline for converting Unity `.anim` files (and `.unitypackage` files containing animations) into universally compatible `.vrma` (Virtual Reality Model Animation) files.

## 🚀 How to Use

### 1. Drag-and-Drop (Easiest)
Simply drag and drop an `.anim` file or a `.unitypackage` file directly onto `anim2vrma.bat` in Windows Explorer.
- **If it's an `.anim` file**: It will instantly generate a `.vrma` file right next to it.
- **If it's a `.unitypackage`**: It will silently import the package, automatically detect any new `.anim` files that were added, and batch-convert all of them into `.vrma` files right next to the original package.

### 2. Command Line Interface (CLI)
For automation or scripting, you can invoke the PowerShell orchestrator directly:
```powershell
.\Convert-AnimToVrma.ps1 -InputPath "C:\path\to\your\animation.anim"
```
You can optionally specify an output path using `-OutputPath "C:\path\to\output.vrma"`.

---

## 🏗️ Architecture & Requirements

This pipeline operates by dynamically booting a hidden, headless instance of Unity in batchmode to process the heavy lifting of humanoid bone mapping.

*   **Engine:** Unity 2022.3.62f3 LTS (Mandatory. Unity 6 introduces `TreeViewState` API breakages that destroy UniVRM).
*   **Base Framework:** UniVRM v0.128.0 (Both `VRM` and `UniVRM` packages).
*   **Core Logic:** Malaybaku's `AnimationClipToVrmaCore` (utilizing the "Vector 1" hard-coded reference humanoid to map generic Unity muscles into the strict VRM 1.0 bone specification).
*   **Glue:** `VrmaCliConverter.cs` (a custom Editor script that bridges the CLI arguments to the internal C# API).

---

## 🛠️ Custom Fixes Applied

During development, several robust fixes were applied to the open-source toolkits to guarantee stability:

1.  **The 1-Frame Pose Bug:** Malaybaku's original exporter calculated frames by multiplying the clip length by the framerate (`Mathf.FloorToInt(clip.length * 30)`). Single-frame static poses have a length of exactly `0.00s`, resulting in 0 frames and generating mathematically empty `.vrma` files. This was patched to enforce a minimum of 1 frame (`Mathf.Max(1, ...)`), allowing static `.anim` poses to export perfectly.
2.  **Missing Dependencies:** Standard Unity templates strip out packages like `com.unity.test-framework`, `com.unity.modules.animation`, and `com.unity.ugui`. The project's `manifest.json` was surgically rebuilt to include these so the VRM toolkits could compile.
3.  **UnityPackage Auto-Diffing:** The PowerShell script was upgraded to take a state snapshot of the `Assets` folder before and after importing a `.unitypackage`, enabling it to automatically isolate and process only the newly introduced animations.

---

## ⚠️ Known Limitations & Troubleshooting

*   **Incompatible UnityPackages:** If you drag and drop a `.unitypackage` that contains broken or incompatible C# scripts (e.g., a package meant for a different Unity version), Unity will refuse to compile the project, and the batch script will abort with `Scripts have compiler errors`. Ensure asset packs only contain models/animations, or are strictly compatible with Unity 2022.3.
*   **Non-Humanoid Animations:** The converter explicitly requires standard Unity Humanoid animations. Generic/Legacy rigs will be rejected by the internal C# validation check.
*   **Editor Locks:** Ensure the Unity Editor for `"My project"` is **closed** before running the converter. Unity batchmode will instantly fail if the project is already open in a visual Editor window.
