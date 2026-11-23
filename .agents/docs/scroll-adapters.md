# 应用滚动适配器

本文件规定为个别应用接入替代滚动输出的方式。适配器用于目标应用不接受 Mos 标准平滑输出的场景, 例如 iPhone 镜像只读取触控板类 sender 的 phased 事件。

## 何时使用

满足以下全部条件时才新增适配器:

- 问题只出现在特定应用中, 标准路径 (Annotated Session tap + CGEventPostToPid) 的输出对该应用无效或行为错误
- 已用实验确认目标应用需要的事件形式, 实验记录写入 docs/plans 下的方案文档
- 问题无法通过应用例外设置 (Options 中的 Application) 解决

## 目录规范

```text
Mos/ScrollCore/Adapters/
  ScrollAdapter.swift          接入协议: ScrollAdapter, ScrollOutputSink, ScrollAdapterDescriptor, ScrollAdapterRegistration
  ScrollAdapterCenter.swift    注册, 生命周期, 共享 session 层 tap 与捕获闸门
  ScrollAdapterCatalog.swift   已接入适配器的注册表, 新增适配器只需在此追加一项
  Shared/                      可复用的输出与设备组件
    PhasedTrackpadOutput.swift     phased 手势状态机, 事件构造, PhasedTrackpadSink
    VirtualTrackpadIdentity.swift  共享的虚拟 Magic Trackpad 2 身份 (macOS 15+, CoreHID)
    VirtualTrackpadDescriptor.swift
    PhasedWindowScrollAdapter.swift  窗口缓存, 命中判断与虚拟触控板输出的共享实现
  Calendar/
    CalendarScrollAdapter.swift    macOS 26+ 的 Calendar 月视图与年视图内容区
  <AppName>/                   单个应用的适配器, 一个应用一个目录
    <AppName>Adapter.swift
```

测试放在 MosTests, 新建测试文件需要手动加入 MosTests target (Mos 源码目录是同步目录, 测试目录不是)。

## 接入步骤

1. 在 Mos/ScrollCore/Adapters/<AppName>/ 下新建适配器类, 实现 ScrollAdapter
2. 用静态 descriptor 声明 identifier, bundleIdentifiers 与 minimumSystemVersion
3. 输出优先复用 Shared 中的组件; 需要新的输出形式时, 在 Shared 中实现新的 ScrollOutputSink
4. 在 ScrollAdapterCatalog.registrations 中追加 ScrollAdapterRegistration
5. 为状态机, 字段构造和路由判断补单测, 跑 Debug build 与相关 MosTests
6. 在 docs/plans 下记录实验依据, 设计决策与已知风险

## 协议约定

| 成员 | 调用线程 | 约束 |
|---|---|---|
| activate / deactivate | 主线程 | 目标应用启动或退出时调用; 共享资源 (如 VirtualTrackpadIdentity) 在此 retain / release |
| refresh | 主线程 | 激活期间由 ScrollAdapterCenter 定时调用: 目标应用在前台时每 0.25 秒, 否则每 1 秒; 显示器参数变化时适配器可自行补一次。只做廉价查询, 查不到目标时自行降低全量扫描频率 |
| route(at:) | 主线程, 滚动热路径 | 先用缓存粗筛; 必须的跨进程查询只在粗筛命中后执行且结果有缓存; 不分配对象, 不写日志; 返回 nil 表示放行 |
| ScrollOutputSink.frame / end | 投递队列 | 串行调用; end 在没有进行中手势时为空操作 |
| ScrollOutputSink.preparePassthrough | tap 回调线程 | 同步目标应用额外读取的字段, 默认空实现 |

## 系统版本门槛

- minimumSystemVersion 是唯一的版本门槛。ScrollAdapterCenter 启动时按当前系统过滤注册项, 不满足的注册项不会调用 make, 也不会注册任何 NSWorkspace 监听
- 全部注册项都不满足时, ScrollAdapterCenter 不注册监听, 不创建 tap, 不运行定时器
- 依赖高版本框架时, 在使用点加 #available 并在链接设置中弱链接该框架 (示例: OTHER_LDFLAGS 中的 -weak_framework CoreHID), 低版本系统上仍能启动

## 配置与会话

平滑滚动详细设置中的 Application compatibility scrolling (应用兼容滚动) 控制适配器启用状态, 默认开启. 全局设置和应用例外共用该配置; 应用选择继承时跟随全局, 取消继承时使用自身配置

| 条件 | 行为 |
|---|---|
| 应用兼容滚动关闭 | 停用对应适配器, 释放其虚拟设备引用, 后续输入使用标准路径 |
| 白名单模式中没有匹配的应用条目 | 适配器保持停用, 平滑和反向均跳过 |
| 平滑关闭或临时禁用平滑热键按下 | 原始事件按反向设置放行, 新的平滑帧停止产生 |
| 只有一个轴开启平滑 | 开启的轴进入插值; 另一个轴原样放行, 反向设置分别生效 |
| 设置变化或临时禁用平滑热键按下 | 当前适配器会话结束, 旧代次的排队帧失效 |
| 目标进程或适配器输出端变化 | 结束前一会话并清空插值残余, 再开始新会话 |

适配器输出端自行生成手势阶段. Simulate Trackpad (模拟触控板) 仍控制标准路径的 phase / momentum 字段; 适配器继续读取常规平滑参数. 两个开关具有独立作用

全局配置使用 smoothAppCompatibility 键. 应用配置中的同名字段为可选值, 缺失时按开启处理; 旧应用配置继续正常解码. 设置变化期间, 适配器 tap 已处理的放行事件仍按时间戳跳过标准路径的第二次处理

## Calendar 范围

Calendar 适配器注册 com.apple.iCal, 最低版本为 macOS 26.0. 窗口检测复用 PhasedWindowScrollAdapter, 输出复用虚拟触控板身份与 phased 手势状态机. Calendar 输出另含 type 29 的手势序列开始和结束事件, subtype 分别为 61 和 62

CalendarScrollScope 在后台队列读取主窗口 CALMainWindow 的 views-switcher 与 active-view. 仅 month-button 或 year-button 单独选中时接受内容区域. 日视图, 周视图, 侧栏和工具栏沿用标准路径. 辅助功能结构读取失败时暂停 Calendar 适配; 查询具有超时, 缓存有效期为 2 秒. 滚动回调与投递队列读取缓存

视图选择变化时结束 Calendar 当前适配器会话. 识别刷新沿用框架的前台 0.25 秒和后台 1 秒间隔, 视图切换具有相应的缓存延迟

## 设计决策

- Calendar 的早期相关反馈见 [Mos #132](https://github.com/Caldis/Mos/issues/132): 2019 年的 macOS 10.12.6 月视图无法滚动. [Mac Mouse Fix #1558](https://github.com/noah-nuebling/mac-mouse-fix/issues/1558) 在 2025-09-19 明确记录 macOS 26.0 月/年视图异常. 本次兼容起点按用户选择限定为 26.0; 早期报告与当前幅度跳跃问题的根因关系仍待验证
- [LinearMouse #1224](https://github.com/linearmouse/linearmouse/pull/1224) 补充了触控板式手势边界和伴随事件. Calendar profile 采用该事件结构, 沿用 Mos 已有的虚拟 sender 和 HID 层输出. [后续反馈 #1290](https://github.com/linearmouse/linearmouse/issues/1290) 仍有慢速卡顿与快速反弹, 因此手感与跨月/跨年幅度需要人工验收
- 独立兼容开关保留常规平滑、反向和应用例外语义, 同时提供退回标准输出的入口

## 验证范围

自动化测试覆盖版本门槛、月/年视图标识、手势边界字段、旧配置解码、开关继承、分轴设置、目标切换和过期帧丢弃. 实际 Calendar 滚动幅度、顺滑程度、日/周视图回归及 iPhone 镜像手感由用户测试

HID 投递仍跟随当前光标. 队列中的帧检查缓存内容矩形, 矩形内部临时出现遮挡窗口时仍存在命中缓存延迟; 进入窗口时捕获尚未启用的第一格滚动也可能使用标准路径

## 运行时开销约束

- 目标应用未运行: 标准路径每个滚动事件只多读一个布尔值 (ScrollAdapterCenter.isArmed)
- 目标应用运行: 共享 session 层 tap 已创建但处于禁用状态; 只有光标进入目标窗口且该位置最上层窗口属于目标应用, 或目标应用切到前台时才启用。光标离开后, 下一次刷新或窗口外的第一个滚动事件禁用 tap; 系统禁用 tap 时同步关闭闸门, 由标准路径接手
- 全部适配器共用一个 session 层 tap, 新增适配器不新增 tap
- Debug 构建以环境变量 MOS_DISABLE_SCROLL_ADAPTERS=1 启动时不启用任何适配器, 用于同一二进制的开销对照 (open --env MOS_DISABLE_SCROLL_ADAPTERS=1 <app>)
- 不在 route(at:) 与 sink 中调用 CGWindowList, AX, IOKit; 窗口列表类查询放在 refresh 中。NSWindow.windowNumber(at:) 只能在主线程调用, 只在粗筛命中后执行并缓存结果

## 已知陷阱

- 写入行位移 (CGEvent 字段 11 / 12) 会按 1 行 = 8 像素重算定点位移与像素位移, 构造事件时必须先写行位移
- 从 HID 层投递的事件会把光标移到事件的 location; 不要写入固定位置 (会把光标锁在原地), 新建事件默认取创建时的光标位置。HID 层事件投递给光标下的窗口, 光标离开目标窗口后放弃手势 (不发送 Ended, 以免送往其他应用) 并丢弃剩余帧, 由下一次手势开头的打断信号复位接收方
- eventSourceUserData 一经写入非零值便无法覆盖; 不要用它标记来源进程可能已写过的事件, 改用位置或状态判断
- Annotated Session 层之前的事件没有可用的目标 pid: session 层的目标 pid 字段是前台应用, HID 层为空, 字段 91 / 92 (mouseEventWindowUnderMousePointer) 在滚动事件中为 0 (2026-10-12 实测)。目标应用由适配器给出 (ScrollAdapterRoute.application)
- sender (字段 87) 是内核分配的注册表 ID, 无法自定义; 填入不存在的 ID 会被接收方当作无效来源
- 适配器 tap 消费的事件不会到达 Annotated Session tap; 放行的事件会再经过一次标准路径, ScrollAdapterCenter.screenStandardScroll 按事件时间戳跳过同一事件 (不按位置: 两次回调之间窗口缓存可能刷新, 也有事件从未经过适配器 tap)
- 判断目标窗口时先用缓存的窗口矩形粗筛, 位于矩形内再用 NSWindow.windowNumber(at:belowWindowWithWindowNumber:) 取该位置最上层的窗口 (约 35 到 66 µs, 结果按位置缓存 50 ms; Mac Mouse Fix 采用同一做法)。只用窗口矩形会接管遮挡在目标窗口上的其他应用的滚动; 在 Annotated Session 层拦截无法阻止 iPhone 镜像收到原始滚轮
