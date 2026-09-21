using UnityEditor;
using UnityEngine;
using System.IO;
using System;
using System.Linq;

// UniHumanoid's BVH importer (bvhAssetPostprocessor.cs) embeds the resulting
// AnimationClip as a sub-asset inside a .prefab file, not as its own
// standalone .anim file - but VrmaCliConverter.ConvertFromCommandLine only
// knows how to AssetDatabase.LoadAssetAtPath<AnimationClip> a real .anim
// file (the main asset at that path). This extracts the embedded clip out
// into a real, standalone .anim asset so the existing converter can process
// it unchanged.
public class BvhBridgeExtractor
{
    public static void ExtractFromCommandLine()
    {
        try
        {
            string prefabPath = null;
            string outPath = null;

            string[] args = System.Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-prefabPath" && i + 1 < args.Length)
                    prefabPath = args[i + 1];
                if (args[i] == "-outPath" && i + 1 < args.Length)
                    outPath = args[i + 1];
            }

            if (string.IsNullOrEmpty(prefabPath) || string.IsNullOrEmpty(outPath))
            {
                Debug.LogError("BvhBridgeExtractor: -prefabPath and -outPath are both required.");
                EditorApplication.Exit(1);
                return;
            }

            var allAssets = AssetDatabase.LoadAllAssetsAtPath(prefabPath);
            var clip = allAssets.OfType<AnimationClip>().FirstOrDefault();
            if (clip == null)
            {
                Debug.LogError($"BvhBridgeExtractor: No AnimationClip sub-asset found at {prefabPath}.");
                EditorApplication.Exit(1);
                return;
            }

            Debug.Log($"BvhBridgeExtractor: Found clip '{clip.name}', isHumanMotion={clip.isHumanMotion}, length={clip.length}");

            // AssetDatabase.CreateAsset needs a fresh copy - the sub-asset
            // object itself is still owned by the prefab file.
            var clipCopy = UnityEngine.Object.Instantiate(clip);
            clipCopy.name = clip.name;
            AssetDatabase.CreateAsset(clipCopy, outPath);
            AssetDatabase.SaveAssets();

            Debug.Log($"BvhBridgeExtractor: Extracted to {outPath}");
            EditorApplication.Exit(0);
        }
        catch (Exception e)
        {
            Debug.LogError($"BvhBridgeExtractor: Exception: {e}");
            EditorApplication.Exit(1);
        }
    }
}
