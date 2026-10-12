# Mirroring Scroll Lab 代码阅读指南

本文面向准备评审 Lab 关键代码、并据此决定 Mos 开发方向的开发者。全文先给出系统层级模型，再按阅读顺序标出每个关键位置，最后列出尚未查清的系统行为

## 1. 系统层级模型

一次滚轮输入在 macOS 中依次经过以下层级，自下而上：

| 层级 | 组件 | Lab 中的对应位置 |
|---|---|---|
| 1 硬件与驱动 | 物理设备或虚拟设备, 由 IOKit HID 驱动解析报文 | VirtualDevices.swift |
| 2 HID 事件系统 | IOHIDEventSystem, 应用自然滚动翻转与滚轮加速, 触控板手势识别也在此层之下完成 | 只能间接影响 |
| 3 CGEvent 管线 | WindowServer 生成 CGEvent, 依次经过 HID tap, Session tap, Annotated Session tap | TapController.swift, CGOutput |
| 4 应用 | NSEvent, 或 iPhone 镜像的输入读取点 | 观测对象 |

已经确认的事实如下：

- iPhone 镜像读取滚动的位置位于第 3 层底部附近。Mos 的 tap 挂在 Annotated Session 层，处于最上游之后，因此改写不到镜像收到的事件。这就是 issue #762 的根因
- 在 HID tap 吞掉原始事件并重新投递，可以影响镜像。投递普通滚轮时，镜像内表现为分段滚动
- 第 1 层注入的虚拟设备与真实硬件没有区别：
  - 虚拟鼠标的滚轮报文会经过第 2 层的滚轮加速，每格位移随报文频率增大，最高约 95pt。通过设备属性无法关闭这一加速
  - 伪装为 Magic Trackpad 2 的虚拟设备会被 AppleMultitouchTrackpadHIDEventDriver 接管，系统为它生成带阶段标记的原生触控板滚动和惯性。镜像在这种输入下首次出现了顺滑滚动

## 2. 推荐阅读顺序

### 2.1 事件入口: TapController.swift

1. 文件头注释说明 tap 链顺序与 iPhone 镜像的读取位置
2. install (约第 47 行): tap 的位置和插入点来自配置，事件掩码只包含 scrollWheel 和 keyDown
3. handle (约第 77 行): 每个滚动事件的处理分支
   - 自身事件判定：UserData 标记，或字段 87 命中虚拟设备的服务 ID
   - 范围判定，连续输入过滤，原地改写分支
   - 计算三种增量后交给引擎，再按配置吞掉原始事件
4. 字段 87 是事件来源 IOHIDEventService 的注册表 ID，由 hidEventServiceIDs (VirtualDevices.swift 约第 233 行) 按厂商 ID 和产品 ID 查询得到。早期版本靠指针位移学习来源 ID，会把物理鼠标误判为自身，已经废弃

### 2.2 帧调度与插值: ScrollEngine.swift

1. 类注释描述一次会话的生命周期：输入累积，按帧输出，空闲后结束
2. input (约第 95 行): 运行在 engine 队列；没有计时器时开启新会话并记录 Trace
3. Mos 插值，依次对应 Mos 源码中的三处实现：
   - mosAccumulate (约第 211 行): 步长下限、速度倍率、同向累加与反向重置，对应 Mos ScrollCore.handleScroll 与 ScrollPoster.update
   - mosTick (约第 222 行): 每帧移动剩余距离的 trans 比例，经过 MosFilter，再按死区判断是否输出，对应 ScrollPoster.processing
   - mosTransition 与 MosFilter (文件开头): 对应 Mos 的 generateDurationTransition 与 ScrollFilter
4. emitFrame (约第 258 行): 同一帧距离在各输出方式下的换算
   - wheelRepost 与 phasedScroll 生成 CGEvent，经 CGOutput 投递
   - virtualMouse 换算成滚轮单位
   - magicTrackpad 换算成手指位移，包含落指静止帧与触边重新落指
5. finishIfIdle (约第 192 行) 与 endGesture (约第 367 行): 会话结束条件、Ended 事件、抬指与合成惯性
6. CGOutput.phased (约第 431 行): 触控板式 CGEvent 的字段组合，各字段编号见 Support.swift 的 Field

### 2.3 虚拟设备: VirtualDevices.swift

1. VirtualDevice (文件开头): CoreHID 设备的创建、报文串行发送与重建。发送失败会写入监视区并计入会话记录
2. VirtualMouse: 标准鼠标描述符；wheel 中根据系统自然滚动设置换算方向
3. Magic Trackpad 2 部分 (MARK 注释处):
   - 设备身份：厂商 ID 0x05AC，产品 ID 0x0281，传输方式 I2C
   - MT2Delegate: 驱动握手时的特性报文应答，数值取自 VoodooInput。每次请求都会写入监视区，便于观察驱动是否重新握手
   - touch 与 lift: 落指、移动与抬指序列，每次落指分配新的触点 ID
   - report: 输入报文 0x02 的字节布局，函数注释逐位说明
4. VirtualTouchpad: 通用数字化仪触控板，系统只产生无子类型的手势事件，作为对照保留

### 2.4 诊断: Trace.swift 与 TraceViews.swift

- 三条采样流：引擎收到的输入，引擎每帧输出，在 tap 观测到的自身输出事件
- 会话记录统计输入数、引擎帧数、输出事件数、惯性帧数与发送失败数
- 引擎帧数大于 0 且输出事件为 0 的会话标记为"无输出事件"，即目前间歇失效的表现

## 3. 尚未查清的问题

### 3.1 虚拟妙控板间歇失效

现象：同样的滚轮输入，有的会话得到完整的开始、持续、结束序列，有的会话只得到 MayBegin 与 Cancelled，或者完全没有事件

已观测的事实：

- 驱动握手只在设备创建时发生一次
- 失效时报文发送没有返回错误
- 每次落指改用新的触点 ID，并在最后位置抬指之后，失效仍然存在
- 增加落指静止帧和每帧上报后，失效比例没有稳定改善
- 测试期间存在用户的真实滚动输入，样本受到干扰，上述比例只能作为参考

待验证的方向：

- 真实触控板的报文时序。手指接触期间按固定频率上报，压力与接触面积会逐渐变化。当前实现的压力和面积是常量
- 时间戳字段的单位与回绕方式，以及驱动是否依据它判断手指静止
- 系统的误触抑制：键盘输入或其他指针设备活动后，触控板输入会在短时间内被忽略
- 驱动对内置设备标记的处理。该虚拟设备在 hidutil 中显示为内置设备

建议的取证方式：

1. 用会话记录确认失效会话的引擎帧数与输出事件数
2. 在监视区对照失效会话前后的驱动请求日志
3. 用 ioreg 观察 AppleMultitouchDevice 在失效前后的属性变化

### 3.2 产品化前需要单独评估的约束

- 伪装苹果硬件依赖未公开的协议，系统更新可能改变驱动行为
- 苹果授予的是虚拟设备权限，正式版用它冒充苹果设备是否合规，需要单独确认
- CoreHID 要求 macOS 15 及以上，Mos 的最低版本是 10.13

## 4. 相关文件

| 文件 | 内容 |
|---|---|
| experiments/MirroringHIDProbe/Sources/MirroringHIDProbe/MagicTrackpadProbe.swift | 命令行版虚拟妙控板探针, 可单独复现握手与一次滑动 |
| experiments/MirroringHIDProbe/tools/evspy.swift | HID tap 监听工具, 打印滚动与手势事件字段 |
| docs/research/iphone-mirroring-scroll/ | 根因研究与历次实验记录 |
| Mos/ScrollCore/ScrollPoster.swift | Mos 平滑滚动的原始实现, Lab 的 Mos 插值与之逐项对应 |
