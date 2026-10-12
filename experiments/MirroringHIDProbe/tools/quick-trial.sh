#!/bin/zsh
# quick-trial.sh <标签> <命令...>: 在一次输入前后截取窗口, 打印内容位移 (点)
T=${0:A:h}; WC=$T/.build/winctl; Q=${OUT_ROOT:-/tmp}/quick; mkdir -p $Q
L=$($WC list iPhone | head -1); WID=$(echo "$L" | sed -E 's/id=([0-9]+).*/\1/')
eval $(echo "$L" | sed -E 's/.* x=([-0-9.]+) y=([-0-9.]+) w=([0-9.]+) h=([0-9.]+).*/X=\1 Y=\2 W=\3 H=\4/')
CX=$(( ${X%.*} + ${W%.*} / 2 )); CY=$(( ${Y%.*} + ${H%.*} * 45 / 100 ))
label=$1; shift
open -a "iPhone Mirroring"; sleep 0.3
$WC warp $CX $CY; $WC move $((CX + 1)) $CY; sleep 0.15
screencapture -x -o -l $WID $Q/$label-a.png
"$@" >/dev/null 2>&1; sleep 1.6
screencapture -x -o -l $WID $Q/$label-b.png
python3 - $Q/$label-a.png $Q/$label-b.png $label <<'PY'
import sys, numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert('L').resize((326, 720)), dtype=np.float32)
b = np.asarray(Image.open(sys.argv[2]).convert('L').resize((326, 720)), dtype=np.float32)
top, bot, xa, xb = 250, 470, 30, 296
band = a[top:bot, xa:xb]
best = min(((dy, float(np.mean(np.abs(band - b[top+dy:bot+dy, xa:xb])))) for dy in range(-240, 241)), key=lambda t: t[1])
print(f"{sys.argv[3]}: content_dy={best[0]}pt err={best[1]:.2f} err0={float(np.mean(np.abs(band - b[top:bot, xa:xb]))):.2f}")
PY
