using UnityEditor;
using UnityEngine;
using System;
using System.Linq;

// Sets a freshly-imported FBX's rig to Humanoid and lets Unity's own
// automatic bone-mapper (the same one behind the Rig tab's "Configure..."
// button) build the Avatar, since BVH has no native Unity importer and
// UniHumanoid's BVH importer only produces a legacy (non-Humanoid) clip -
// see BvhBridgeExtractor.cs for that dead end. FBX is the real bridge:
// Unity's own FBX importer does genuine Humanoid muscle-space retargeting.
public class FbxHumanoidSetup
{
    public static void SetupFromCommandLine()
    {
        try
        {
            string fbxPath = null;
            string[] args = System.Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-fbxPath" && i + 1 < args.Length)
                    fbxPath = args[i + 1];
            }

            if (string.IsNullOrEmpty(fbxPath))
            {
                Debug.LogError("FbxHumanoidSetup: -fbxPath is required.");
                EditorApplication.Exit(1);
                return;
            }

            var importer = AssetImporter.GetAtPath(fbxPath) as ModelImporter;
            if (importer == null)
            {
                Debug.LogError($"FbxHumanoidSetup: No ModelImporter at {fbxPath}.");
                EditorApplication.Exit(1);
                return;
            }

            importer.animationType = ModelImporterAnimationType.Human;
            importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            importer.SaveAndReimport();

            var avatar = AssetDatabase.LoadAllAssetsAtPath(fbxPath).OfType<Avatar>().FirstOrDefault();
            var clip = AssetDatabase.LoadAllAssetsAtPath(fbxPath).OfType<AnimationClip>().FirstOrDefault();

            Debug.Log($"FbxHumanoidSetup: avatar={(avatar != null ? avatar.name : "null")}, avatar.isValid={(avatar != null ? avatar.isValid.ToString() : "n/a")}, avatar.isHuman={(avatar != null ? avatar.isHuman.ToString() : "n/a")}");
            Debug.Log($"FbxHumanoidSetup: clip={(clip != null ? clip.name : "null")}, clip.isHumanMotion={(clip != null ? clip.isHumanMotion.ToString() : "n/a")}, clip.legacy={(clip != null ? clip.legacy.ToString() : "n/a")}");

            EditorApplication.Exit(0);
        }
        catch (Exception e)
        {
            Debug.LogError($"FbxHumanoidSetup: Exception: {e}");
            EditorApplication.Exit(1);
        }
    }
}
