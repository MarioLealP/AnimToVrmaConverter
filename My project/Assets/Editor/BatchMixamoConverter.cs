using UnityEditor;
using UnityEngine;
using System;
using System.IO;
using System.Linq;
using Baxter;

// Processes an entire folder tree of Mixamo .fbx files in ONE Unity session
// - each subfolder path relative to -sourceRoot becomes the output tag
// (e.g. sourceRoot/emotion/happy/Cheering.fbx -> outputRoot/emotion/happy/
// cheering.vrma). Built for "hundreds of animations" (Mario, 2026-09-21) -
// Convert-MixamoFbx.ps1's per-file approach launches Unity twice per file,
// and Unity's own startup/domain-reload overhead alone is several seconds
// each time; at hundreds of files that's plausibly hours of pure launch
// overhead before any real conversion work happens. This does the whole
// import -> Humanoid setup -> extract -> VRMA export chain per file
// in-process, using the same underlying calls FbxHumanoidSetup.cs,
// BvhBridgeExtractor.cs and VrmaCliConverter.cs already use individually,
// without ever restarting Unity between files.
public class BatchMixamoConverter
{
    public static void RunFromCommandLine()
    {
        try
        {
            string sourceRoot = null;
            string outputRoot = null;
            string[] args = System.Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-sourceRoot" && i + 1 < args.Length) sourceRoot = args[i + 1];
                if (args[i] == "-outputRoot" && i + 1 < args.Length) outputRoot = args[i + 1];
            }
            if (string.IsNullOrEmpty(sourceRoot) || string.IsNullOrEmpty(outputRoot))
            {
                Debug.LogError("BatchMixamoConverter: -sourceRoot and -outputRoot are both required.");
                EditorApplication.Exit(1);
                return;
            }
            if (!Directory.Exists(sourceRoot))
            {
                Debug.LogError($"BatchMixamoConverter: -sourceRoot does not exist: {sourceRoot}");
                EditorApplication.Exit(1);
                return;
            }

            var fbxFiles = Directory.GetFiles(sourceRoot, "*.fbx", SearchOption.AllDirectories);
            Debug.Log($"BatchMixamoConverter: found {fbxFiles.Length} fbx file(s) under {sourceRoot}");

            string batchImportDir = Path.Combine(Application.dataPath, "BatchImport");
            Directory.CreateDirectory(batchImportDir);

            int ok = 0, failed = 0, skipped = 0;

            foreach (var srcPath in fbxFiles)
            {
                string relDir = Path.GetDirectoryName(srcPath).Substring(sourceRoot.Length).Trim('\\', '/');
                string tag = relDir.Replace('\\', '/');
                string baseName = Path.GetFileNameWithoutExtension(srcPath);
                string safeName = new string(baseName.Select(c => char.IsLetterOrDigit(c) ? char.ToLower(c) : '_').ToArray());
                while (safeName.Contains("__")) safeName = safeName.Replace("__", "_");
                safeName = safeName.Trim('_');

                string outDir = string.IsNullOrEmpty(tag) ? outputRoot : Path.Combine(outputRoot, tag);
                Directory.CreateDirectory(outDir);
                string outVrmaPath = Path.Combine(outDir, safeName + ".vrma");

                if (File.Exists(outVrmaPath))
                {
                    skipped++;
                    continue; // resumable - a crash/interruption partway through doesn't mean starting over
                }

                string assetsFbxRel = "Assets/BatchImport/" + Guid.NewGuid().ToString("N").Substring(0, 12) + ".fbx";
                GameObject animatorObject = null;
                try
                {
                    File.Copy(srcPath, Path.Combine(Application.dataPath, "..", assetsFbxRel), true);
                    AssetDatabase.ImportAsset(assetsFbxRel, ImportAssetOptions.ForceUpdate);

                    var importer = AssetImporter.GetAtPath(assetsFbxRel) as ModelImporter;
                    importer.animationType = ModelImporterAnimationType.Human;
                    importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
                    importer.SaveAndReimport();

                    var allAssets = AssetDatabase.LoadAllAssetsAtPath(assetsFbxRel);
                    var avatar = allAssets.OfType<Avatar>().FirstOrDefault();
                    var clip = allAssets.OfType<AnimationClip>().FirstOrDefault();

                    if (avatar == null || !avatar.isValid || !avatar.isHuman || clip == null || !clip.isHumanMotion)
                    {
                        Debug.LogWarning($"BatchMixamoConverter: SKIP (not a valid Humanoid clip) - {srcPath}");
                        failed++;
                        continue;
                    }

                    var animator = HumanoidBuilder.CreateHumanoid(ReferenceHumanoid.BoneLocalPoseMap);
                    animatorObject = animator.gameObject;
                    var bytes = AnimationClipToVrmaCore.Create(animator, clip);
                    File.WriteAllBytes(outVrmaPath, bytes);
                    ok++;
                    Debug.Log($"BatchMixamoConverter: OK {tag}/{safeName}.vrma");
                }
                catch (Exception e)
                {
                    Debug.LogError($"BatchMixamoConverter: FAILED {srcPath}: {e.Message}");
                    failed++;
                }
                finally
                {
                    if (animatorObject != null) UnityEngine.Object.DestroyImmediate(animatorObject);
                    if (AssetDatabase.LoadAssetAtPath<GameObject>(assetsFbxRel) != null)
                    {
                        AssetDatabase.DeleteAsset(assetsFbxRel);
                    }
                }
            }

            Debug.Log($"BatchMixamoConverter: done. ok={ok} failed={failed} skipped={skipped} total={fbxFiles.Length}");
            EditorApplication.Exit(0);
        }
        catch (Exception e)
        {
            Debug.LogError($"BatchMixamoConverter: Exception: {e}");
            EditorApplication.Exit(1);
        }
    }
}
