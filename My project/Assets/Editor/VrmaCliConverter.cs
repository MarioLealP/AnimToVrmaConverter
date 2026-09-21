using UnityEditor;
using UnityEngine;
using System.IO;
using System;
using Baxter;

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

            if (!clip.isHumanMotion)
            {
                Debug.LogError($"VrmaCliConverter: Animation clip {clip.name} is not a Humanoid clip.");
                EditorApplication.Exit(1);
                return;
            }

            Debug.Log($"VrmaCliConverter: Loaded humanoid clip {clip.name}. Beginning Vector 1 conversion...");

            GameObject animatorObject = null;
            try
            {
                // Instantiate the hard-coded reference humanoid from Malaybaku's toolkit (Vector 1)
                var animator = HumanoidBuilder.CreateHumanoid(ReferenceHumanoid.BoneLocalPoseMap);
                animatorObject = animator.gameObject;
                
                // Export to VRMA using the core logic
                var bytes = AnimationClipToVrmaCore.Create(animator, clip);
                
                // Save
                File.WriteAllBytes(outputPath, bytes);
                Debug.Log($"VrmaCliConverter: Successfully exported VRMA to {outputPath}");
            }
            finally
            {
                if (animatorObject != null)
                {
                    UnityEngine.Object.DestroyImmediate(animatorObject);
                }
            }

            // Cleanup temp file if we copied it
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
