"""Headless Blender BVH -> FBX conversion, so Unity's native FBX importer
(which does real Humanoid muscle-space retargeting, unlike UniHumanoid's
BVH importer which only produces a legacy Transform-curve clip - confirmed
by reading BvhImporterContext.cs's own `Animation.legacy = true`) has
something it can actually import as a Humanoid animation.

Usage: blender.exe --background --python bvh_to_fbx.py -- <in.bvh> <out.fbx>
"""
import sys
import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
bvh_path, fbx_path = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)

bpy.ops.import_anim.bvh(
    filepath=bvh_path,
    axis_forward="-Z",
    axis_up="Y",
    rotate_mode="NATIVE",
    global_scale=0.01,  # BVH is in cm (per this project's exports), Blender/Unity want meters
    # Without this, the scene keeps its default 24fps while the BVH's
    # actual frame time (0.05s = 20fps) still places keyframes correctly
    # in TIME - so exporting bakes at 24 scene-frames/sec against a clip
    # timed for 20, stretching/distorting duration (confirmed: a 60-frame/
    # 3.0s source came out as a 10.375s FBX clip; playback looked "wonky").
    update_scene_fps=True,
)

# FBX export bakes the SCENE's frame range, not the imported action's own
# range - a fresh scene defaults to frame_end=250 regardless of how long
# the actual imported motion is, so without this the bake padded the real
# 60-frame/3.0s clip out to a 250-frame/12.5s one (confirmed: 250/20=12.5s,
# matched the observed distorted duration almost exactly). Every armature
# object here comes straight from this one BVH import, so any one of their
# actions has the real range to match the scene to.
for obj in bpy.data.objects:
    if obj.animation_data and obj.animation_data.action:
        frame_start, frame_end = obj.animation_data.action.frame_range
        bpy.context.scene.frame_start = int(frame_start)
        bpy.context.scene.frame_end = int(frame_end)
        break

bpy.ops.export_scene.fbx(
    filepath=fbx_path,
    use_selection=False,
    add_leaf_bones=False,
    bake_anim=True,
    bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=False,
    bake_anim_force_startend_keying=True,
)

print(f"Exported FBX: {fbx_path}")
