using UnityEngine;
using UnityEditor;

public class GenerateDanceAnim
{
    public static void Generate()
    {
        AnimationClip clip = new AnimationClip();
        clip.frameRate = 30;

        // Make it loop
        var settings = AnimationUtility.GetAnimationClipSettings(clip);
        settings.loopTime = true;
        AnimationUtility.SetAnimationClipSettings(clip, settings);

        // Add some humanoid muscle curves (e.g., Spine Front-Back, Left Arm Down-Up)
        // 0 = Spine Front-Back, etc. We can just use standard Humanoid property names.
        
        // Let's animate Spine Front-Back (Muscle 4 or similar, but we can use property names)
        // Actually, property names for Humanoid Animator are specific: "Animator.Spine Front-Back" etc.
        // Let's animate Root Transform Position just to be simple, but it must be Humanoid.
        // For Humanoid, Root Transform is "RootT.x", "RootT.y", "RootT.z" and "RootQ.x" etc.
        // Or we can just animate a muscle: "Spine Front-Back"
        
        AnimationCurve curve = AnimationCurve.EaseInOut(0f, -0.5f, 1f, 0.5f);
        curve.AddKey(2f, -0.5f); // Ping pong back
        clip.SetCurve("", typeof(Animator), "Spine Front-Back", curve);
        
        AnimationCurve armCurve = AnimationCurve.EaseInOut(0f, -0.8f, 1f, 0.8f);
        armCurve.AddKey(2f, -0.8f);
        clip.SetCurve("", typeof(Animator), "LeftArm Down-Up", armCurve);
        clip.SetCurve("", typeof(Animator), "RightArm Down-Up", armCurve);

        // Save the asset
        AssetDatabase.CreateAsset(clip, "Assets/ProceduralDance.anim");
        AssetDatabase.SaveAssets();
        
        Debug.Log("Created Assets/ProceduralDance.anim");
    }
}
