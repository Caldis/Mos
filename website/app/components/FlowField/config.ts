// Shared configuration for the FlowField background particle effect.
// Every tunable knob lives here so the runtime defaults and the dev control
// panel stay in sync from a single source of truth.

export type FlowFieldConfig = {
  // Particles
  densityDesktop: number; // particles per area on fine (mouse) pointers
  densityCoarse: number; // particles per area on coarse (touch) pointers
  countMin: number; // lower clamp on particle count
  countMax: number; // upper clamp on particle count

  // Motion
  damping: number; // velocity retained each frame (0..1)
  dampingScroll: number; // damping delta added at full scroll (may be negative)
  accel: number; // flow-field acceleration magnitude
  speedBase: number; // base travel speed
  speedScroll: number; // extra speed at full scroll

  // Flow field (the trig field that steers particles)
  fieldScaleX: number;
  fieldScaleY: number;
  fieldScaleXY: number;
  angleMul: number; // field value -> angle, multiplied by PI
  timeX: number; // temporal evolution rates
  timeY: number;
  timeXY: number;

  // Pointer interaction
  influenceR: number; // pointer swirl radius in px
  swirl: number; // pointer swirl strength

  // Rendering / trails
  fade: number; // per-frame erase amount (higher = shorter trail / cleaner)
  fadeScroll: number; // extra erase at full scroll
  lineWidth: number;
  opacityA: number; // stroke opacities for the 3 particle tiers
  opacityB: number;
  opacityC: number;
};

export const DEFAULT_CONFIG: FlowFieldConfig = {
  densityDesktop: 2,
  densityCoarse: 1,
  countMin: 800,
  countMax: 2000,

  damping: 0.83,
  dampingScroll: 0.14,
  accel: 1.15,
  speedBase: 0.2,
  speedScroll: 0,

  fieldScaleX: 0.003,
  fieldScaleY: 0.002,
  fieldScaleXY: 0.001,
  angleMul: 0.1,
  timeX: 0,
  timeY: 0.00015,
  timeXY: 0.00035,

  influenceR: 490,
  swirl: 3,

  fade: 0.115,
  fadeScroll: 0.3,
  lineWidth: 1.25,
  opacityA: 0.5,
  opacityB: 0.43,
  opacityC: 0.36,
};

export type ControlSpec = {
  key: keyof FlowFieldConfig;
  label: string; // Chinese label shown in the dev panel
  desc: string; // one-line Chinese explanation of what the knob does
  min: number;
  max: number;
  step: number;
};

export type ControlGroup = {
  group: string;
  items: ControlSpec[];
};

// Slider schema for the dev control panel (labels/descriptions in Chinese).
export const FLOW_FIELD_CONTROLS: ControlGroup[] = [
  {
    group: "粒子",
    items: [
      { key: "densityDesktop", label: "密度（鼠标）", desc: "鼠标设备上每单位面积的粒子数量", min: 0.1, max: 2, step: 0.05 },
      { key: "densityCoarse", label: "密度（触屏）", desc: "触屏设备上每单位面积的粒子数量", min: 0.05, max: 1, step: 0.05 },
      { key: "countMin", label: "数量下限", desc: "粒子总数的最小值（小屏时兜底）", min: 0, max: 800, step: 10 },
      { key: "countMax", label: "数量上限", desc: "粒子总数的最大值（大屏时封顶）", min: 100, max: 2000, step: 20 },
    ],
  },
  {
    group: "运动",
    items: [
      { key: "damping", label: "阻尼", desc: "每帧保留的速度比例；越大越顺滑飘逸", min: 0.5, max: 0.99, step: 0.01 },
      { key: "dampingScroll", label: "阻尼·随滚动", desc: "页面滚到底时叠加到阻尼上的增量（可为负）", min: -0.4, max: 0.4, step: 0.01 },
      { key: "accel", label: "流场加速度", desc: "流场对粒子的转向加速强度", min: 0.05, max: 2, step: 0.05 },
      { key: "speedBase", label: "基础速度", desc: "粒子的基础移动速度", min: 0, max: 3, step: 0.05 },
      { key: "speedScroll", label: "速度·随滚动", desc: "页面滚到底时额外叠加的速度", min: 0, max: 4, step: 0.05 },
    ],
  },
  {
    group: "流场",
    items: [
      { key: "fieldScaleX", label: "缩放 X", desc: "X 方向流场频率；越大纹理越细碎", min: 0.0002, max: 0.01, step: 0.0002 },
      { key: "fieldScaleY", label: "缩放 Y", desc: "Y 方向流场频率", min: 0.0002, max: 0.01, step: 0.0002 },
      { key: "fieldScaleXY", label: "缩放 X+Y", desc: "对角方向流场频率", min: 0.0002, max: 0.01, step: 0.0002 },
      { key: "angleMul", label: "角度 ×π", desc: "流场值映射到转向角的倍率", min: 0, max: 6, step: 0.1 },
      { key: "timeX", label: "时间 X", desc: "X 层流场随时间演化的速度", min: 0, max: 0.003, step: 0.00005 },
      { key: "timeY", label: "时间 Y", desc: "Y 层流场随时间演化的速度", min: 0, max: 0.003, step: 0.00005 },
      { key: "timeXY", label: "时间 X+Y", desc: "对角层流场随时间演化的速度", min: 0, max: 0.003, step: 0.00005 },
    ],
  },
  {
    group: "指针",
    items: [
      { key: "influenceR", label: "影响半径", desc: "鼠标周围产生漩涡的半径（像素）", min: 0, max: 500, step: 10 },
      { key: "swirl", label: "漩涡强度", desc: "鼠标牵引粒子打旋的强度", min: 0, max: 3, step: 0.05 },
    ],
  },
  {
    group: "拖尾",
    items: [
      { key: "fade", label: "擦除量", desc: "每帧擦除的拖尾比例；越大拖尾越短、越干净", min: 0, max: 0.5, step: 0.005 },
      { key: "fadeScroll", label: "擦除·随滚动", desc: "页面滚到底时额外增加的擦除量", min: 0, max: 0.3, step: 0.005 },
      { key: "lineWidth", label: "线宽", desc: "粒子轨迹的线条粗细", min: 0.25, max: 4, step: 0.25 },
      { key: "opacityA", label: "不透明度 A", desc: "第 1 组粒子描边的不透明度（最亮）", min: 0, max: 0.5, step: 0.01 },
      { key: "opacityB", label: "不透明度 B", desc: "第 2 组粒子描边的不透明度", min: 0, max: 0.5, step: 0.01 },
      { key: "opacityC", label: "不透明度 C", desc: "第 3 组粒子描边的不透明度（最暗）", min: 0, max: 0.5, step: 0.01 },
    ],
  },
];
