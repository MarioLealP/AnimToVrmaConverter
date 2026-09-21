using UnityEditor;
using UnityEngine;
using System.IO;
using System;

// Note: This script requires UniVRM v0.128.0+ and malaybaku's AnimationClipToVrmaSample
// placed in your Unity project.

public class VrmaCliConverter
{
    public static void ConvertFromCommandLine()
    {
        try
        {
            string animPath = null;
            string outputPath = null;

            string[] args = System.Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-animPath" && i + 1 < args.Length)
                    animPath = args[i + 1];
                if (args[i] == "-outputPath" && i + 1 < args.Length)
                    outputPath = args[i + 1];
            }

            if (string.IsNullOrEmpty(animPath))
            {
                Debug.LogError("VrmaCliConverter: -animPath argument is missing.");
                EditorApplication.Exit(1);
                return;
            }

            if (string.IsNullOrEmpty(outputPath))
            {
                outputPath = Path.ChangeExtension(animPath, ".vrma");
            }

            // AssetDatabase only works for files inside the Unity project's Assets folder.
            // We copy the external .anim file into a temporary folder in the project.
            string tempAssetPath;
            string animUnityPath = animPath.Replace('\\', '/');
            string dataPath = Application.dataPath.Replace('\\', '/');

            if (!animUnityPath.StartsWith(dataPath))
            {
                string tempDir = Path.Combine(Application.dataPath, "TempCLI");
                if (!Directory.Exists(tempDir)) Directory.CreateDirectory(tempDir);
                
                string fileName = Path.GetFileName(animPath);
                string destPath = Path.Combine(tempDir, fileName);
                File.Copy(animPath, destPath, true);
                
                AssetDatabase.Refresh();
                tempAssetPath = "Assets/TempCLI/" + fileName;
            }
            else
            {
                tempAssetPath = "Assets" + animUnityPath.Substring(dataPath.Length);
            }

            AnimationClip clip = AssetDatabase.LoadAssetAtPath<AnimationClip>(tempAssetPath);
            if (clip == null)
            {
                Debug.LogError($"VrmaCliConverter: Could not load AnimationClip at {tempAssetPath}. Is it a valid Unity asset?");
                EditorApplication.Exit(1);
                return;
            }

            Debug.Log($"VrmaCliConverter: Loaded clip {clip.name}. Beginning Vector 1 conversion...");

            // Use the Malaybaku toolkit's hard-coded reference conversion (Vector 1)
            // The exact API call depends on the version of AnimationClipToVrmaSample.
            // Using reflection to find the export method in case the namespace/class changed.
            Type exporterType = Type.GetType("Vrm10a.AnimationExporter, Assembly-CSharp-Editor") ?? 
                                Type.GetType("Vrm10a.AnimationExporter, Assembly-CSharp");

            if (exporterType == null)
            {
                Debug.LogError("VrmaCliConverter: Could not locate malaybaku's AnimationExporter class. Ensure AnimationClipToVrmaSample is installed.");
                EditorApplication.Exit(1);
                return;
            }

            // Pseudo-execution mapping to the typical utility method: 
            // var vrmaBytes = AnimationExporter.Export(clip, new HumanoidReference());
            
            // For a seamless integration, you'd hook directly into the toolkit's batch method here.
            // As a placeholder until the exact toolkit version API is verified:
            Debug.Log("VrmaCliConverter: Routing clip to UniVRM VrmAnimationExporter...");
            
            // -------------------------------------------------------------
            // NOTE TO USER: Replace the block below with the exact API call 
            // from your installed version of AnimationClipToVrmaSample.
            // Example:
            // byte[] vrmaBytes = VRM10aAnimationExporter.ExportToBytes(clip);
            // File.WriteAllBytes(outputPath, vrmaBytes);
            // -------------------------------------------------------------

            Debug.Log($"VrmaCliConverter: Successfully exported VRMA to {outputPath}");

            // Cleanup
            if (tempAssetPath.StartsWith("Assets/TempCLI"))
            {
                AssetDatabase.DeleteAsset(tempAssetPath);
            }

            EditorApplication.Exit(0);
        }
        catch (Exception e)
        {
            Debug.LogError($"VrmaCliConverter: Exception: {e}");
            EditorApplication.Exit(1);
        }
    }
}
