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
| refresh | 主线程 | 激活期间每 0.25 秒调用; 只做廉价查询, 结果写入缓存。目标应用不在前台或查不到目标时自行降频 |
| route(at:) | 主线程, 滚动热路径 | 先用缓存粗筛; 必须的跨进程查询只在粗筛命中后执行且结果有缓存; 不分配对象, 不写日志; 返回 nil 表示放行 |
| ScrollOutputSink.frame / end | 投递队列 | 串行调用; end 在没有进行中手势时为空操作 |
| ScrollOutputSink.preparePassthrough | tap 回调线程 | 同步目标应用额外读取的字段, 默认空实现 |

## 系统版本门槛

- minimumSystemVersion 是唯一的版本门槛。ScrollAdapterCenter 启动时按当前系统过滤注册项, 不满足的注册项不会调用 make, 也不会注册任何 NSWorkspace 监听
- 全部注册项都不满足时, ScrollAdapterCenter 不注册监听, 不创建 tap, 不运行定时器
- 依赖高版本框架时, 在使用点加 #available 并在链接设置中弱链接该框架 (示例: OTHER_LDFLAGS 中的 -weak_framework CoreHID), 低版本系统上仍能启动

## 运行时开销约束

- 目标应用未运行: 标准路径每个滚动事件只多读一个布尔值 (ScrollAdapterCenter.isArmed)
- 目标应用运行: 共享 session 层 tap 已创建但处于禁用状态; 只有光标进入目标窗口且该位置最上层窗口属于目标应用, 或目标应用切到前台时才启用。光标离开后, 下一次刷新或窗口外的第一个滚动事件禁用 tap; 系统禁用 tap 时同步关闭闸门, 由标准路径接手
- 全部适配器共用一个 session 层 tap, 新增适配器不新增 tap
- 不在 route(at:) 与 sink 中调用 CGWindowList, AX, IOKit; 窗口列表类查询放在 refresh 中。NSWindow.windowNumber(at:) 只能在主线程调用, 只在粗筛命中后执行并缓存结果

## 已知陷阱

- 写入行位移 (CGEvent 字段 11 / 12) 会按 1 行 = 8 像素重算定点位移与像素位移, 构造事件时必须先写行位移
- 从 HID 层投递的事件会把光标移到事件的 location; 不要写入固定位置 (会把光标锁在原地), 新建事件默认取创建时的光标位置。HID 层事件投递给光标下的窗口, 光标离开目标窗口后放弃手势 (不发送 Ended, 以免送往其他应用) 并丢弃剩余帧, 由下一次手势开头的打断信号复位接收方
- eventSourceUserData 一经写入非零值便无法覆盖; 不要用它标记来源进程可能已写过的事件, 改用位置或状态判断
- Annotated Session 层之前的事件没有可用的目标 pid: session 层的目标 pid 字段是前台应用, HID 层为空, 字段 91 / 92 (mouseEventWindowUnderMousePointer) 在滚动事件中为 0 (2026-10-12 实测)。目标应用由适配器给出 (ScrollAdapterRoute.application)
- sender (字段 87) 是内核分配的注册表 ID, 无法自定义; 填入不存在的 ID 会被接收方当作无效来源
- 适配器 tap 消费的事件不会到达 Annotated Session tap; 放行的事件会再经过一次标准路径, ScrollAdapterCenter.screenStandardScroll 按事件时间戳跳过同一事件 (不按位置: 两次回调之间窗口缓存可能刷新, 也有事件从未经过适配器 tap)
- 判断目标窗口时先用缓存的窗口矩形粗筛, 位于矩形内再用 NSWindow.windowNumber(at:belowWindowWithWindowNumber:) 取该位置最上层的窗口 (约 35 到 66 µs, 结果按位置缓存 50 ms; Mac Mouse Fix 采用同一做法)。只用窗口矩形会接管遮挡在目标窗口上的其他应用的滚动; 在 Annotated Session 层拦截无法阻止 iPhone 镜像收到原始滚轮
