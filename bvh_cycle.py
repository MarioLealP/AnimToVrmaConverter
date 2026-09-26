"""Cut one seamless, in-place gait cycle out of a straight-line mocap walk BVH.

The Bandai Namco Research Motion Dataset walks are 5-16 s takes: stand, walk
~8 m along +Z, stop. Felt's overlay moves her itself (main.gd, constant
speed) and loops the walk-cycle clip until arrival, so what's needed is one
in-place cycle whose last frame flows into its first.

1. Steady region: the longest run of frames where the hips' horizontal speed is within 20 % of
   the take's median walking speed (drops the start/stop).
2. Cycle: the shortest length (0.7-1.8 s) at which a frame pair (a, b)
   inside that run has near-best pose similarity (all rotation channels,
   wrapped degrees), taking the best pair for that length. Frames a..b+1 are
   written (see the sampler note in main()).
3. In place: the hips' X/Z drift over the cycle is removed linearly (their
   side-to-side sway stays), and the cycle starts at X=Z=0.

Prints the natural walking speed in m/s: main.gd must move her at about
that speed while this clip plays, or her feet slide.

Usage: uv run --no-project python bvh_cycle.py in.bvh out.bvh
"""
import math, sys


def parse(path):
    lines = open(path).read().splitlines()
    mi = next(i for i, l in enumerate(lines) if l.strip() == "MOTION")
    header = lines[:mi]
    joints, chans = [], []  # chans: (joint, channel_name)
    for l in header:
        t = l.split()
        if t and t[0] in ("ROOT", "JOINT"):
            joints.append(t[1])
        if t and t[0] == "CHANNELS":
            for c in t[2:]:
                chans.append((joints[-1], c))
    frame_time = float(lines[mi + 2].split()[-1])
    frames = [[float(v) for v in l.split()] for l in lines[mi + 3:] if l.strip()]
    return header, chans, frame_time, frames


def main(src, dst):
    header, chans, ft, frames = parse(src)
    idx = {c: i for i, c in enumerate(chans)}
    hx, hz = idx[("Hips", "Xposition")], idx[("Hips", "Zposition")]
    rot = [i for i, (j, c) in enumerate(chans) if c.endswith("rotation")]
    n = len(frames)
    # per-frame horizontal hips speed (cm/s), smoothed over ~1.2 s (about one
    # slow gait cycle, so per-step surges of slow/sad walks average out)
    w = max(1, int(0.6 / ft))
    sp = []
    for i in range(n):
        a, b = max(0, i - w), min(n - 1, i + w)
        d = math.hypot(frames[b][hx] - frames[a][hx], frames[b][hz] - frames[a][hz])
        sp.append(d / ((b - a) * ft) if b > a else 0)
    moving = sorted(s for s in sp if s > 20)
    if not moving:
        raise SystemExit(f"{src}: no walking found")
    med = moving[len(moving) // 2]
    ok = [abs(sp[i] - med) < 0.2 * med for i in range(n)]
    # longest contiguous steady run
    runs, start = [], None
    for i in range(n + 1):
        if i < n and ok[i]:
            start = i if start is None else start
        elif start is not None:
            runs.append((start, i - 1)); start = None
    lo, hi = max(runs, key=lambda r: r[1] - r[0])
    # the smoothing window blurs into the start/stop: stay 1.5 s clear of both ends
    lo, hi = max(lo, int(1.5 / ft)), min(hi, n - 2 - int(1.5 / ft))

    def pose_dist(a, b):
        return sum(abs((frames[a][i] - frames[b][i] + 180) % 360 - 180) for i in rot) / len(rot)

    # best seam per cycle length, then the SHORTEST length that is a local
    # minimum close to the global best (otherwise 2 cycles often win narrowly)
    per_len = {}
    for L in range(int(0.7 / ft), int(1.8 / ft) + 1):
        cands = [(pose_dist(a, a + L), a) for a in range(lo, hi - L + 1)]
        if cands:
            per_len[L] = min(cands)
    if not per_len:
        raise SystemExit(f"{src}: steady region too short ({(hi - lo) * ft:.2f}s)")
    dmin = min(v[0] for v in per_len.values())
    Ls = sorted(per_len)
    pick = None
    for k, L in enumerate(Ls):
        d = per_len[L][0]
        left = per_len[Ls[k - 1]][0] if k > 0 else float("inf")
        right = per_len[Ls[k + 1]][0] if k + 1 < len(Ls) else float("inf")
        if d <= left and d <= right and d <= dmin * 1.5 + 0.3:
            pick = L
            break
    best = (per_len[pick][0], per_len[pick][1], per_len[pick][1] + pick)
    dist, a, b = best
    L = b - a
    x0, z0 = frames[a][hx], frames[a][hz]
    dx, dz = frames[b][hx] - x0, frames[b][hz] - z0
    out = []
    # a..b+1: AnimationClipToVrmaCore samples floor(length*30) frames and the
    # FBX length comes out a hair short, so two spare frames make the sampled
    # clip end at b-1 or b (b ~ a): no skipped frames at the loop seam
    for k in range(L + 2):
        f = list(frames[a + k])
        f[hx] = f[hx] - x0 - dx * k / L
        f[hz] = f[hz] - z0 - dz * k / L
        out.append(f)
    speed = math.hypot(dx, dz) / 100 / (L * ft)
    with open(dst, "w") as fh:
        fh.write("\n".join(header) + "\nMOTION\n")
        fh.write(f"Frames: {L}\nFrame Time: {ft}\n")
        for f in out:
            fh.write(" ".join(f"{v:.6g}" for v in f) + "\n")
    print(f"{src}: steady {lo * ft:.1f}-{hi * ft:.1f}s, cycle frames {a}-{b} "
          f"({L * ft:.2f}s), seam error {dist:.1f} deg avg, speed {speed:.2f} m/s")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
