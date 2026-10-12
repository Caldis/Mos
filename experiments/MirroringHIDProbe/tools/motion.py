# motion.py <video.mov>: 计算录屏中每帧内容的纵向位移
# 输出滚动段的紧凑时间线与平滑度指标
import sys, os, subprocess, glob, re, json
import numpy as np
from PIL import Image
video = sys.argv[1]
out = video + ".frames"
os.makedirs(out, exist_ok=True)
for f in glob.glob(out + "/*.png"): os.remove(f)
log = subprocess.run(["ffmpeg", "-v", "info", "-i", video, "-vf", "scale=iw/2:ih/2,showinfo", "-fps_mode", "passthrough",
                      out + "/f%05d.png"], capture_output=True, text=True).stderr
times = [float(m) for m in re.findall(r"pts_time:([0-9.]+)", log)]
files = sorted(glob.glob(out + "/*.png"))
frames = [np.asarray(Image.open(f).convert("L"), dtype=np.float32) for f in files]
h, w = frames[0].shape
top, bot, xa, xb = int(h*.25), int(h*.75), int(w*.10), int(w*.90)
R = 150   # max per-frame shift searched (points, at half scale = 1x points)
def _search(a, b, top, bot, xa, xb, cands):
    band = a[top:bot, xa:xb]
    best = None
    for dy in cands:
        if top + dy < 0 or bot + dy > b.shape[0]: continue
        e = float(np.mean(np.abs(band - b[top+dy:bot+dy, xa:xb])))
        if best is None or e < best[1] or (e == best[1] and abs(dy) < abs(best[0])): best = (dy, e)
    return best
def shift(a, b):
    # 先在四分之一尺寸粗搜, 再在二分之一尺寸细化
    qa, qb = a[::2, ::2], b[::2, ::2]
    qh, qw = qa.shape
    c = _search(qa, qb, int(qh*.25), int(qh*.75), int(qw*.10), int(qw*.90), range(-R//2, R//2 + 1))
    guess = c[0] * 2
    return _search(a, b, top, bot, xa, xb, range(guess - 3, guess + 4))
res = []
for i in range(1, len(frames)):
    dy, err = shift(frames[i-1], frames[i])
    res.append((times[i] if i < len(times) else i/60, dy, err))
moving = [r for r in res if r[1] != 0]
if not moving:
    print(json.dumps({"frames": len(frames), "moving": 0}))
    json.dump({"summary": {"moving_frames": 0}, "t": [r[0] for r in res], "dy": [0 for r in res], "err": [r[2] for r in res]},
              open(video.rsplit(".", 1)[0] + ".json", "w"))
    sys.exit()
t0, t1 = moving[0][0], moving[-1][0]
seg = [r for r in res if t0 <= r[0] <= t1]
d = np.array([abs(r[1]) for r in seg])
dt = np.diff([r[0] for r in seg]) if len(seg) > 1 else np.array([0])
summary = {
    "frames_total": len(frames), "scroll_duration_s": round(t1 - t0, 3), "frames_in_segment": len(seg),
    "moving_frames": int((d > 0).sum()), "still_frames_in_segment": int((d == 0).sum()),
    "total_px_halfscale": int(d.sum()), "max_jump": int(d.max()), "median_jump_moving": float(np.median(d[d > 0])),
    "max_frame_gap_ms": round(float(dt.max())*1000, 1) if len(dt) else 0, "max_err": round(max(r[2] for r in seg), 2),
}
print(json.dumps(summary))
print("timeline(dy per frame):", " ".join(str(r[1]) for r in seg))
json.dump({"summary": summary, "t": [r[0] for r in res], "dy": [r[1] for r in res], "err": [r[2] for r in res]},
          open(video.rsplit(".", 1)[0] + ".json", "w"))
