"""Headless Blender: BVH whose rest pose is NOT a T-pose -> FBX with a real
T-pose rest and the same world-space motion.

Why: bvh_to_fbx.py is fine for SMPL-derived BVH (T-pose rest). The Bandai
Namco Research Motion Dataset's BVH rest pose has every chain lying along +X
(spine, arms and legs alike; frame rotations stand it up). Unity's Humanoid
avatar takes the model's rest pose as its T-pose reference, so that rest
would wreck the muscle-space retarget.

How:
  A = the imported, animated armature.
  B = a copy of A, posed like A's first frame, then every bone swung
      (minimal rotation, parents first) to T-pose directions for the facing
      the character has on average over the clip: spine/neck/head up, legs down, arms
      out sideways, feet/toes forward. Swinging from a real pose (not from
      the lying rest) keeps natural twist, e.g. palms end up facing down.
      That pose is applied as B's rest.
  Every B bone gets a world-space Copy Transforms of its A twin, baked, and
  A is deleted, so B moves exactly like A (same bone lengths) but rests in
  a T-pose. Export settings match bvh_to_fbx.py.

Usage: blender.exe --background --python bvh_to_fbx_tpose.py -- <in.bvh> <out.fbx>
Bone names expected (Bandai): Hips Spine Chest Neck Head Shoulder_L/R
UpperArm_L/R LowerArm_L/R Hand_L/R UpperLeg_L/R LowerLeg_L/R Foot_L/R Toes_L/R.
"""
import sys
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
bvh_path, fbx_path = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_anim.bvh(
    filepath=bvh_path, axis_forward="-Z", axis_up="Y", rotate_mode="NATIVE",
    global_scale=0.01, update_scene_fps=True,
)
scene = bpy.context.scene
A = bpy.context.object
fs, fe = (int(v) for v in A.animation_data.action.frame_range)
scene.frame_start, scene.frame_end = fs, fe
scene.frame_set(fs)
vl = bpy.context.view_layer

B = A.copy()
B.data = A.data.copy()
B.animation_data_clear()
scene.collection.objects.link(B)
B.name = "Armature"
vl.update()


def hierarchy(arm):
    out = []
    def walk(b):
        out.append(b.name)
        for c in b.children:
            walk(c)
    for b in arm.data.bones:
        if b.parent is None:
            walk(b)
    return out


order = hierarchy(B)
Aw, Bw = A.matrix_world, B.matrix_world

# 1) B takes A's first-frame pose
for name in order:
    B.pose.bones[name].matrix = Bw.inverted() @ Aw @ A.pose.bones[name].matrix
    vl.update()


def wpos(name):
    return (Bw @ B.pose.bones[name].matrix).translation


# 2) facing: the hips' left-right axis averaged over the whole clip (one
#    frame mid-stride can be 10+ degrees off the travel direction)
up = Vector((0, 0, 1))
left = Vector((0, 0, 0))
for f in range(fs, fe + 1):
    scene.frame_set(f)
    left += (Aw @ A.pose.bones["UpperLeg_L"].matrix).translation - (Aw @ A.pose.bones["UpperLeg_R"].matrix).translation
scene.frame_set(fs)
vl.update()
left.z = 0
left.normalize()
fwd = left.cross(up).normalized()
targets = {
    "Hips": up, "Spine": up, "Chest": up, "Neck": up, "Head": up,
    "Shoulder_L": left, "UpperArm_L": left, "LowerArm_L": left, "Hand_L": left,
    "Shoulder_R": -left, "UpperArm_R": -left, "LowerArm_R": -left, "Hand_R": -left,
    "UpperLeg_L": -up, "LowerLeg_L": -up, "UpperLeg_R": -up, "LowerLeg_R": -up,
    "Foot_L": (fwd - 0.6 * up).normalized(), "Foot_R": (fwd - 0.6 * up).normalized(),
    "Toes_L": fwd, "Toes_R": fwd,
}
for name in order:
    if name not in targets:
        continue
    pb = B.pose.bones[name]
    wm = Bw @ pb.matrix
    head = wm.translation.copy()
    cur = wm.to_3x3().col[1].normalized()  # bone Y axis = its direction
    q = cur.rotation_difference(targets[name])
    nw = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ wm
    pb.matrix = Bw.inverted() @ nw
    vl.update()

# 3) that pose becomes B's rest
for o in scene.objects:
    o.select_set(False)
B.select_set(True)
vl.objects.active = B
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)
for pb in B.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)

# 4) follow A in world space, bake, drop A
for pb in B.pose.bones:
    c = pb.constraints.new("COPY_TRANSFORMS")
    c.target, c.subtarget = A, pb.name
    c.owner_space = c.target_space = "WORLD"
bpy.ops.pose.select_all(action="SELECT")
bpy.ops.nla.bake(frame_start=fs, frame_end=fe, only_selected=False, visual_keying=True,
                 clear_constraints=True, use_current_action=False, bake_types={"POSE"})
bpy.ops.object.mode_set(mode="OBJECT")
bpy.data.objects.remove(A, do_unlink=True)

bpy.ops.export_scene.fbx(
    filepath=fbx_path, use_selection=False, add_leaf_bones=False, bake_anim=True,
    bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
)
print(f"Exported T-pose FBX: {fbx_path} frames {fs}-{fe} facing {tuple(round(v, 2) for v in fwd)}")
