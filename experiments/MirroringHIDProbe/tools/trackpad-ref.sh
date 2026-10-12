#!/bin/zsh
# 真实触控板基线: 用户滑动时录制镜像窗口和 HID 层事件流
# 用法: trackpad-ref.sh [秒数]
set -u
T=${0:A:h}; B=$T/.build; S=$B; SECS=${1:-6}
OUT=${OUT_ROOT:-/tmp}/trackpad-ref-$(date +%Y%m%d-%H%M%S); mkdir -p $OUT
L=$($S/winctl list iPhone | head -1)
eval $(echo "$L" | sed -E 's/.* x=([-0-9.]+) y=([-0-9.]+) w=([0-9.]+) h=([0-9.]+).*/X=\1 Y=\2 W=\3 H=\4/')
MOS=0; pgrep -x Mos >/dev/null && { MOS=1; osascript -e 'tell application "Mos" to quit'; sleep 1.5; }
open -a "iPhone Mirroring"; sleep 0.5
echo "Recording ${SECS}s: two-finger swipe on the trackpad over the mirroring window now"
$S/evspy $SECS > $OUT/events.log 2>&1 &
screencapture -x -V $SECS -R ${X%.*},${Y%.*},${W%.*},${H%.*} $OUT/trackpad.mov
wait
(( MOS )) && open -a /Applications/Mos.app
python3 $T/motion.py $OUT/trackpad.mov > $OUT/trackpad.motion.txt 2>&1
python3 $T/report.py $OUT
grep -c "t=22" $OUT/events.log | xargs echo "scroll events:"; grep -c "t=29" $OUT/events.log | xargs echo "gesture events:"
