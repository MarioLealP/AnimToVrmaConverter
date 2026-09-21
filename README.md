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

---

## 🤖 Text-to-Animation (T2A): `Generate-Animation.ps1`

A full **text prompt -> `.vrma`** pipeline, confirmed working end to end 2026-09-21. Built directly (an earlier attempt at handing the bridging step to Gemini didn't land, per Mario 2026-09-21: "it's not being too bright or useful, so you gotta do it yourself").

```powershell
.\Generate-Animation.ps1 -Prompt "a person does a backflip" -OutputVrma "C:\path\to\output.vrma"
```

### Pipeline

1. **T2M-GPT** (`Mael-zys/T2M-GPT`, HumanML3D-trained) runs on the Nitro5 laptop's RTX 3060 over SSH (`~/felt-t2a-spike`, `generate_bvh.py`) - text in, ~1.3GB VRAM, well under the laptop's 6GB budget.
2. Inside that same script: `recover_from_ric` -> SMPLify (`joints2smpl`, an iterative GPU optimization fitting SMPL body-model rotations to the generated joint positions - genuinely slow, not a fast forward pass) -> the vendored `smpl2bvh` -> `.bvh`.
3. `bvh_to_fbx.py`: headless Blender converts `.bvh` -> `.fbx`. Necessary because UniHumanoid's own BVH importer (already in this Unity project, from UniVRM) only ever produces a **legacy** clip (`Animation.legacy = true` in its own source) - legacy and Humanoid/Mecanim are different Unity animation systems, and a legacy clip can never satisfy `VrmaCliConverter`'s `isHumanMotion` check. Unity's native FBX importer does real Humanoid muscle-space retargeting; BVH has no such importer.
4. `FbxHumanoidSetup.cs` (Unity Editor script): sets the FBX's rig to Humanoid and lets Unity's own automatic bone-mapper build the Avatar.
5. `BvhBridgeExtractor.cs`: the Humanoid `AnimationClip` comes back as a sub-asset embedded in the FBX/prefab, not a standalone file - `VrmaCliConverter` only loads a real `.anim` file, so this extracts it to one.
6. `Convert-AnimToVrma.ps1` (existing, unchanged) -> the final `.vrma`.

### Bugs found and fixed getting this to actually work

*   **Chaotic root-joint jitter (thousands of units of "drift" in 3 seconds for someone just standing still):** T2M-GPT's raw output is in HumanML3D's **normalized** (mean/std z-scored) space - `recover_from_ric` needs it denormalized first (`pred_pose * std + mean`, using `mean.npy`/`std.npy` from the "extractor" checkpoint bundle, `dataset/prepare/download_extractor.sh` - a separate download from the base pretrained model). Skipping this is what an earlier attempt (Gemini's) missed; it's why that attempt's BVH output looked structurally fine but moved the character wildly around the scene.
*   **BVH -> FBX frame-rate mismatch:** Blender's BVH importer needs `update_scene_fps=True`, or the bake runs at the wrong fps against the source clip's actual timing.
*   **BVH -> FBX duration padding:** FBX export bakes the **scene's** frame range, not the imported action's own range - a fresh Blender scene defaults to `frame_end=250` regardless of how long the actual motion is, silently padding a 3-second clip out to ~10-12 seconds. Fixed by setting `scene.frame_start`/`frame_end` to the action's real `frame_range` before exporting.

### Known limitation: no finger animation

SMPL (used by `joints2smpl`/SMPLify here) has 24 joints total - one wrist/hand joint per side, no individual fingers. Even switching to SMPL-X (which does have finger joints) wouldn't add *animated* fingers: T2M-GPT was trained on HumanML3D, a body-only motion capture dataset with no hand data at all, so there's nothing upstream driving finger motion regardless of which body model does the fitting. Fingers render static. This is a ceiling of the training data, not a pipeline bug.

### Requirements beyond the base pipeline above

*   SSH access to `clockmost-nitro5` (the Nitro5 laptop, shared with Ollama/ComfyUI - hand-swapped for its 6GB VRAM, check `nvidia-smi` before assuming it's free) with `~/felt-t2a-spike` set up (T2M-GPT clone + `uv` venv + pretrained model + extractor checkpoint + SMPL body model, see that directory's own state for the exact setup).
*   Blender (tested with 5.2, `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`).
*   `sample_output/save_sample.py` (run via `uv run python save_sample.py` in `~/felt-t2a-spike`) is a smaller standalone reference for generating just the raw HumanML3D pose `.npy` without running the rest of the pipeline - useful for quickly checking what the model itself produces for a prompt.

---

## 🎬 Mixamo animations: `Convert-MixamoFbx.ps1`

Much simpler than the T2A pipeline above - Mixamo FBX is already a real
Humanoid-rigged animation, so there's no laptop/SSH/GPU/SMPLify/Blender step
at all, just the same Unity-side machinery Generate-Animation.ps1 already
uses past the BVH stage (~40s total, confirmed working 2026-09-21).

```powershell
.\Convert-MixamoFbx.ps1 -FbxPath "C:\path\to\downloaded.fbx" -OutputVrma "C:\path\to\output.vrma"
```

Mixamo (mixamo.com) requires an Adobe account login through the browser and
has no public API - there's no way to fetch animations programmatically, so
downloading the `.fbx` yourself first is unavoidable. This script picks up
from there: import as Humanoid, extract the clip, convert to `.vrma`.
