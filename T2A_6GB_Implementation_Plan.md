# Hand-Off Blueprint: Direct Text-to-Animation (T2A) Pipeline (6GB VRAM Constrained)

## 🎯 Executive Summary
The goal is to build a local, end-to-end pipeline that takes a natural language prompt (e.g., "a character doing a backflip") and outputs an engine-ready `.vrma` animation file. 

Because the target hardware is constrained to a **6GB VRAM GPU**, we are explicitly abandoning the cascaded Text-to-Video approach. Video diffusion (predicting millions of pixels) requires 12GB-24GB+ VRAM. Instead, we are utilizing **Direct Text-to-Motion (T2M)** architectures, which predict lightweight mathematical arrays (skeletal joint rotations), easily fitting within a 3GB-5GB VRAM budget.

---

## 🏗️ Pipeline Architecture

The pipeline consists of four distinct phases, bridging Python-based machine learning inference with our already-completed C#/Unity headless serialization engine.

### Phase 1: Local Inference Environment (Python)
*   **Core Tech:** Python 3.10+, PyTorch (CUDA enabled).
*   **Model Selection:** We will target lightweight, open-source T2M models such as **MDM (Human Motion Diffusion Model)** or **T2M-GPT**.
*   **VRAM Strategy:** 
    *   Load the text encoder (CLIP ViT-B/32) in `float16`.
    *   Load the motion diffusion/transformer network.
    *   Ensure aggressive garbage collection and `torch.cuda.empty_cache()` between generations to prevent OOM (Out of Memory) spikes.

### Phase 2: Generation (Text -> Raw Kinematics)
*   **Input:** Natural language text prompt.
*   **Process:** The model tokenizes the text via CLIP, passes the embeddings to the motion diffusion network, and iteratively denoises a sequence of poses.
*   **Output:** The raw output is typically parameterized as **SMPL** or **SMPL-X** rotational data (a `.npy` or `.npz` file) containing Euler angles or quaternions for ~24-52 human joints.

### Phase 3: Format Bridging (SMPL -> Unity-Readable Format)
*   **The Challenge:** Unity does not natively read Python `.npy` SMPL arrays. We must translate this raw data into a format Unity understands (like `.bvh`, `.fbx`, or directly to `.anim`).
*   **Implementation Strategy:** 
    *   Use a Python utility (like `smplx2bvh` or `bvh-converter`) to convert the NumPy array into a standard `.bvh` (Biovision Hierarchy) motion capture file.
    *   Alternatively, write a custom Unity Editor script that reads a serialized JSON of the rotations and bakes it into an `.anim` file on the fly. *(Recommendation: `.bvh` is industry standard and easily imported into Unity's Humanoid system).*

### Phase 4: Headless Standardization (Unity -> VRMA)
*   *Note: This phase is already fully developed and tested.*
*   **Input:** The bridged animation file.
*   **Process:** We feed the animation into our existing `Convert-AnimToVrma.ps1` orchestrator. Unity boots headlessly, processes the motion through the Mecanim Humanoid Avatar system (enforcing the strict VRM T-Pose and hips-only translation rules), and serializes it using Malaybaku's `AnimationClipToVrmaCore`.
*   **Output:** A clean, cross-platform `.vrma` file.

---

## 🚦 Next Steps for Implementation

For the developer/agent taking over this implementation, follow these steps in order:

1.  **Clone & Setup T2M Repository:** Select either `MDM` (HumanMotionDiffusion) or `T2M-GPT` from GitHub. Setup a dedicated Python virtual environment (using `uv` or `conda`) and install PyTorch with the correct CUDA toolkit for the host machine.
2.  **Verify 6GB VRAM Feasibility:** Run a baseline text-to-motion inference script using a short prompt to confirm the model executes without hitting CUDA OOM errors. Use `fp16` precision if necessary.
3.  **Build the Bridging Script:** The chosen model will likely spit out an `.npy` or `.mp4` visualization. Locate or write the script required to export the generated motion strictly as a `.bvh` or `.fbx` file.
4.  **Integration Test:** Take the generated `.bvh`, place it in the Unity project, create an `.anim` extraction macro, and pipe it through the existing `anim2vrma.bat` script to verify end-to-end functionality.
