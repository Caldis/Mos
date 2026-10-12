# report.py <会话目录>: 生成小多图 (累计位移与每帧速度) 和汇总表
import sys, json, glob, os
from PIL import Image, ImageDraw
d = sys.argv[1]
rows = []
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    j = json.load(open(f)); rows.append((os.path.basename(f)[:-5], j))
W, H, pad = 900, 170, 40
img = Image.new("RGB", (W, (H + 10) * len(rows) + 10), "white")
dr = ImageDraw.Draw(img)
for i, (name, j) in enumerate(rows):
    y0 = 10 + i * (H + 10)
    dr.rectangle([pad, y0, W - 10, y0 + H], outline=(200, 200, 200))
    t, dy = j["t"], j["dy"]
    if not t: continue
    tmax = max(t[-1], 4.0)
    cum, c = [], 0
    for v in dy: c += v; cum.append(c)
    span = max(1, max(abs(v) for v in cum))
    vmax = max(1, max(abs(v) for v in dy))
    X = lambda tt: pad + (W - 10 - pad) * tt / tmax
    for tt, v in zip(t, dy):   # per-frame velocity bars (grey)
        h = (H / 2 - 4) * v / vmax
        dr.line([X(tt), y0 + H / 2, X(tt), y0 + H / 2 - h], fill=(170, 170, 170), width=2)
    pts = [(X(tt), y0 + H / 2 - (H / 2 - 6) * v / span) for tt, v in zip(t, cum)]
    dr.line(pts, fill=(30, 90, 200), width=2)
    s = j["summary"]
    dr.text((pad + 6, y0 + 4), f"{name}  total={s.get('total_px_halfscale', 0)}pt  moving={s.get('moving_frames', 0)}  still_in_motion={s.get('still_frames_in_segment', 0)}  max_jump={s.get('max_jump', 0)}  dur={s.get('scroll_duration_s', 0)}s", fill=(0, 0, 0))
img.save(os.path.join(d, "chart.png"))
print(f"{'condition':22} {'total':>6} {'dur_s':>6} {'moving':>6} {'still':>6} {'maxjump':>7} {'median':>6}")
for name, j in rows:
    s = j["summary"]
    print(f"{name:22} {s.get('total_px_halfscale', 0):>6} {s.get('scroll_duration_s', 0):>6} {s.get('moving_frames', 0):>6} {s.get('still_frames_in_segment', 0):>6} {s.get('max_jump', 0):>7} {s.get('median_jump_moving', 0):>6}")
