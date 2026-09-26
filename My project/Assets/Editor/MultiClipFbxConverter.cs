using UnityEditor;
using UnityEngine;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Baxter;

// Converts EVERY take in one multi-clip FBX (e.g. Quaternius' Universal
// Animation Library, 43 takes in a single file) to one .vrma per take, in
// one Unity session. BatchMixamoConverter / Convert-MixamoFbx.ps1 only ever
// take the FIRST clip of an FBX (for UAL that is A_TPose), so they can't be
// used for packs shipped as one file.
//
// Args:
//   -fbxPath <abs path>    source FBX (copied into Assets/BatchImport), or a
//                          FOLDER of FBX files: then a file with a single take
//                          is written as <file name>.vrma (e.g. Blender BVH
//                          conversions, whose one take is just "Armature|...")
//   -outDir  <abs path>    one <ClipName>.vrma per take is written here
//   -clips   <a,b,c>       optional: only these take names
//
// Root/clip import settings (bake into pose, rotationOffset...) are NOT
// honoured by AnimationClipToVrmaCore (it samples raw curves; tested
// 2026-09-26, identical output). If a rig comes out facing away, fix the
// .vrma afterwards with AnimToVrmaConverter/vrma_fix_facing.py.
public class MultiClipFbxConverter
{
    static int ok, failed;

    public static void RunFromCommandLine()
    {
        try
        {
            string fbxPath = null, outDir = null, clipsArg = null;
            var args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (args[i] == "-fbxPath") fbxPath = args[i + 1];
                if (args[i] == "-outDir") outDir = args[i + 1];
                if (args[i] == "-clips") clipsArg = args[i + 1];
            }
            bool isDir = !string.IsNullOrEmpty(fbxPath) && Directory.Exists(fbxPath);
            if (string.IsNullOrEmpty(outDir) || !(isDir || File.Exists(fbxPath ?? "")))
            {
                Debug.LogError("MultiClipFbxConverter: -fbxPath (existing file or folder) and -outDir are required.");
                EditorApplication.Exit(1);
                return;
            }
            var wanted = string.IsNullOrEmpty(clipsArg)
                ? null
                : new HashSet<string>(clipsArg.Split(',').Select(s => s.Trim()).Where(s => s.Length > 0));
            Directory.CreateDirectory(outDir);
            Directory.CreateDirectory(Path.Combine(Application.dataPath, "BatchImport"));

            var files = isDir ? Directory.GetFiles(fbxPath, "*.fbx").OrderBy(f => f).ToArray() : new[] { fbxPath };
            ok = 0; failed = 0;
            foreach (var f in files)
                ConvertFile(f, outDir, wanted, isDir);
            Debug.Log($"MultiClipFbxConverter: done. ok={ok} failed={failed}");
            EditorApplication.Exit(failed > 0 && ok == 0 ? 1 : 0);
        }
        catch (Exception e)
        {
            Debug.LogError($"MultiClipFbxConverter: Exception: {e}");
            EditorApplication.Exit(1);
        }
    }

    static void ConvertFile(string fbxPath, string outDir, HashSet<string> wanted, bool nameSingleTakeByFile)
    {
        string rel = "Assets/BatchImport/multi_" + Guid.NewGuid().ToString("N").Substring(0, 10) + ".fbx";
        try
        {
            File.Copy(fbxPath, Path.Combine(Application.dataPath, "..", rel), true);
            AssetDatabase.ImportAsset(rel, ImportAssetOptions.ForceUpdate);

            var importer = (ModelImporter)AssetImporter.GetAtPath(rel);
            importer.animationType = ModelImporterAnimationType.Human;
            importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            importer.SaveAndReimport();

            var all = AssetDatabase.LoadAllAssetsAtPath(rel);
            var avatar = all.OfType<Avatar>().FirstOrDefault();
            Debug.Log($"MultiClipFbxConverter: {Path.GetFileName(fbxPath)} avatar valid={avatar?.isValid} human={avatar?.isHuman}");
            if (avatar == null || !avatar.isValid || !avatar.isHuman)
            {
                Debug.LogError($"MultiClipFbxConverter: Humanoid auto-mapping failed for {fbxPath}.");
                failed++;
                return;
            }
            if (ok + failed == 0 && avatar.humanDescription.human != null)
            {
                foreach (var hb in avatar.humanDescription.human)
                    Debug.Log($"MultiClipFbxConverter: map {hb.humanName} <- {hb.boneName}");
            }

            var clips = all.OfType<AnimationClip>().Where(c => !c.name.StartsWith("__preview__")).ToList();
            foreach (var clip in clips)
            {
                // Blender-exported takes are named "Armature|Idle_Loop"
                string shortName = clip.name.Substring(clip.name.LastIndexOf('|') + 1);
                if (wanted != null && !wanted.Contains(shortName)) continue;
                string outName = nameSingleTakeByFile && clips.Count == 1
                    ? Path.GetFileNameWithoutExtension(fbxPath)
                    : shortName;
                GameObject go = null;
                try
                {
                    if (!clip.isHumanMotion)
                    {
                        Debug.LogWarning($"MultiClipFbxConverter: SKIP not humanoid - {clip.name}");
                        failed++;
                        continue;
                    }
                    var animator = HumanoidBuilder.CreateHumanoid(ReferenceHumanoid.BoneLocalPoseMap);
                    go = animator.gameObject;
                    var bytes = AnimationClipToVrmaCore.Create(animator, clip);
                    File.WriteAllBytes(Path.Combine(outDir, outName + ".vrma"), bytes);
                    ok++;
                    Debug.Log($"MultiClipFbxConverter: OK {outName} ({clip.length:F2}s)");
                }
                catch (Exception e)
                {
                    Debug.LogError($"MultiClipFbxConverter: FAILED {clip.name}: {e.Message}");
                    failed++;
                }
                finally
                {
                    if (go != null) UnityEngine.Object.DestroyImmediate(go);
                }
            }
        }
        finally
        {
            AssetDatabase.DeleteAsset(rel);
        }
    }
}
