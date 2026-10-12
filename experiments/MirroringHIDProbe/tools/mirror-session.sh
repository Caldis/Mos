#!/bin/zsh
# iPhone 镜像平滑滚动对比测试
# 前提: iPhone 镜像已连接, Safari 停在长页面, 期间无人操作鼠标和触控板
# 用法: mirror-session.sh [用例 ...]   (默认全部)
set -u
T=${0:A:h}; B=$T/.build; S=$B
APP=$T/../DerivedData/Build/Products/Debug/MirroringHIDProbe.app/Contents/MacOS/MirroringHIDProbe
OUT=${OUT_ROOT:-/tmp}/mirror-session-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT
L=$($S/winctl list iPhone | head -1)
[[ -z "$L" ]] && { echo "ABORT: iPhone Mirroring window not found"; exit 1; }
WID=$(echo "$L" | sed -E 's/id=([0-9]+).*/\1/')
eval $(echo "$L" | sed -E 's/.* x=([-0-9.]+) y=([-0-9.]+) w=([0-9.]+) h=([0-9.]+).*/X=\1 Y=\2 W=\3 H=\4/')
(( ${W%.*} < 200 )) && { echo "ABORT: mirroring window too small (${W}x${H}), not connected?"; exit 1; }
CX=$(( ${X%.*} + ${W%.*} / 2 )); CY=$(( ${Y%.*} + ${H%.*} * 45 / 100 ))
echo "window $WID at $X,$Y ${W}x${H}; pointer $CX,$CY; out $OUT"
# The disconnected placeholder ("iPhone 使用中") exposes an AXButton (连接/Connect) in the window; a live mirror does not.
MPID=$(pgrep -f "iPhone Mirroring.app/Contents/MacOS" | head -1)
$S/winctl axdump $MPID | sed '/AXMenuBar/,$d' | grep -q "AXButton" && { echo "ABORT: iPhone Mirroring shows the disconnected placeholder"; exit 1; }
[[ -n "${DRY:-}" ]] && { echo "DRY run: preflight passed, nothing posted"; exit 0; }
MOS=0; pgrep -x Mos >/dev/null && { MOS=1; osascript -e 'tell application "Mos" to quit'; sleep 1.5; }
OLD=$($S/winctl where | tr -d '() ')
cleanup() { $S/winctl warp ${OLD%,*} ${OLD#*,}; (( MOS )) && open -a /Applications/Mos.app; }
trap cleanup EXIT
open -a "iPhone Mirroring"; sleep 0.8
enter() { $S/winctl warp $CX $CY; $S/winctl move $((CX + 1)) $CY; sleep 0.12; }
rec() { local label=$1 secs=$2; shift 2
  echo "== $label: $*"
  # screencapture -V 启动约 1.4 秒后才开始写入, 先预录, 确保输入落在片段内
  screencapture -x -V $((secs + 2)) -R ${X%.*},${Y%.*},${W%.*},${H%.*} $OUT/$label.mov & local cp=$!
  sleep 2.2; "$@" > $OUT/$label.log 2>&1; wait $cp; sleep 0.8; }
tp() { enter; $S/winctl tpswipe "$@"; }
# 一串普通滚轮事件之后, iPhone 镜像会忽略随后的 phased 手势; 发送惯性结束, 预备, 取消可以清除该状态
reset_scroll() { $S/winctl rawphase 0 3 0; sleep 0.05; $S/winctl rawphase 128 0 0; sleep 0.05; $S/winctl rawphase 8 0 0; sleep 0.25; }
ph() { enter; reset_scroll; $S/winctl phase "$@"; }
typeset -A C
C[W1-wheel-notch-up]="rec W1-wheel-notch-up 4 $APP --cycles 1 --warp $CX,$CY --mode notch --direction up"
C[W2-wheel-smooth-down]="rec W2-wheel-smooth-down 4 $APP --cycles 1 --warp $CX,$CY --mode smooth --direction down"
C[T1-drag-down]="rec T1-drag-down 4 tp 9 40 16 0"
C[T2-flick-momentum-up]="rec T2-flick-momentum-up 5 tp -9 12 16 45"
C[T3-count20-delta1-up]="rec T3-count20-delta1-up 4 tp -1 20 16 0"
C[T4-count20-delta30-down]="rec T4-count20-delta30-down 4 tp 30 20 16 0"
C[T5-drag-120hz-down]="rec T5-drag-120hz-down 4 tp 9 60 8 0"
C[V1-virtual-touchpad-up]="rec V1-virtual-touchpad-up 4 $APP --touchpad --cycles 1 --warp $CX,$CY --direction up"
C[P1-drag-30x16ms]="rec P1-drag-30x16ms 4 ph -9 30 16 0"
C[P2-flick-12x8ms]="rec P2-flick-12x8ms 4 ph -9 12 8 0"
C[P3-flick-12x8ms-momentum]="rec P3-flick-12x8ms-momentum 5 ph -9 12 8 45"
C[P4-drag-60x8ms]="rec P4-drag-60x8ms 4 ph -9 60 8 0"
C[P5-slow-20x33ms]="rec P5-slow-20x33ms 4 ph -9 20 33 0"
ORDER=(W1-wheel-notch-up T1-drag-down T2-flick-momentum-up T3-count20-delta1-up T4-count20-delta30-down T5-drag-120hz-down
       P1-drag-30x16ms P2-flick-12x8ms P3-flick-12x8ms-momentum P4-drag-60x8ms P5-slow-20x33ms W2-wheel-smooth-down V1-virtual-touchpad-up)
(( $# )) && ORDER=("$@")
for k in $ORDER; do eval ${C[$k]}; done
cleanup; trap - EXIT
for m in $OUT/*.mov; do python3 $T/motion.py $m > ${m%.mov}.motion.txt 2>&1; done
python3 $T/report.py $OUT
echo "chart: $OUT/chart.png"
