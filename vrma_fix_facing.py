"""Turn a .vrma's whole body about the vertical axis by rewriting the hips track.

Some source rigs come out of the Unity -> AnimationClipToVrmaCore path facing
away from the camera (Quaternius UAL: ~180 deg, confirmed 2026-09-26 by the
hips' forward vector and in the overlay). Unity's clip import settings
(rotationOffset, bake-into-pose) are ignored by that sampler, so the fix is done
on the finished file: pre-multiply every hips rotation key by R_y(yaw) and
rotate every hips translation key by the same R. Every other bone's rotation is
local to its parent, so the whole body follows. Rest-pose nodes are untouched
(importers retarget relative to them).

Usage:
    uv run --no-project python vrma_fix_facing.py [--yaw 180] file.vrma [...]
Files are rewritten in place.
"""
import argparse, json, math, struct


def rewrite(path, yaw_deg):
    b = bytearray(open(path, "rb").read())
    jlen = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(bytes(b[20:20 + jlen]))
    bin_off = 20 + jlen + 8  # start of BIN chunk data
    hips = j["extensions"]["VRMC_vrm_animation"]["humanoid"]["humanBones"]["hips"]["node"]
    h = math.radians(yaw_deg) / 2
    ry = (0.0, math.sin(h), 0.0, math.cos(h))  # x, y, z, w
    c, s = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    touched = 0
    for anim in j["animations"]:
        for ch in anim["channels"]:
            if ch["target"]["node"] != hips:
                continue
            path_kind = ch["target"]["path"]
            acc = j["accessors"][anim["samplers"][ch["sampler"]]["output"]]
            bv = j["bufferViews"][acc["bufferView"]]
            start = bin_off + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            n = {"VEC3": 3, "VEC4": 4}[acc["type"]]
            vals = list(struct.unpack_from("<%df" % (acc["count"] * n), b, start))
            for k in range(acc["count"]):
                v = vals[k * n:(k + 1) * n]
                if path_kind == "rotation":
                    ax, ay, az, aw = ry
                    bx, by, bz, bw = v
                    v = [aw * bx + ax * bw + ay * bz - az * by,
                         aw * by - ax * bz + ay * bw + az * bx,
                         aw * bz + ax * by - ay * bx + az * bw,
                         aw * bw - ax * bx - ay * by - az * bz]
                elif path_kind == "translation":
                    x, y, z = v
                    v = [c * x + s * z, y, -s * x + c * z]
                else:
                    continue
                vals[k * n:(k + 1) * n] = v
            struct.pack_into("<%df" % len(vals), b, start, *vals)
            cols = [vals[i::n] for i in range(n)]
            acc["min"] = [min(col) for col in cols]
            acc["max"] = [max(col) for col in cols]
            touched += 1
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = bytearray(b[:12]) + struct.pack("<I4s", len(js), b"JSON") + js + b[20 + jlen:]
    struct.pack_into("<I", out, 8, len(out))
    open(path, "wb").write(out)
    return touched


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--yaw", type=float, default=180.0)
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    for f in a.files:
        print(f"{f}: rotated {rewrite(f, a.yaw)} hips channel(s) by {a.yaw:g} deg")
