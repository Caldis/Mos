# Logi 接收器多设备并行接管 — 执行交接文档

面向:在新会话中执行本重构的 AI Agent / 开发者
状态:方案已定, 待实现. 本文自包含, 不依赖上一会话上下文
日期:2026-07-08
代码库:/Users/caldis/Desktop/Code/Mos (macOS app "Mos", 分支 master)

## 0. 一句话目标

让 Mos 能同时接管一个 Bolt / Unifying 接收器上多个 Logi 鼠标的 HID++ 按键, 用户在两只鼠标间换手时, 两只的 HID++-only 按键(DPI / 手势 / SmartShift 等)都始终可用, 无需手动在 debug 面板点 slot, 也不产生 retarget 抖动

## 1. 要解决的现象与根因

### 现象

通过 Bolt 接收器连接 MX Master 时, 整个 app 检测不到任何 HID++ 按键, 直到用户第一次在 HID++ debug 面板点击对应 slot(如 Slot 4), 之后全 app 才识别. 用户实际会两只 Logi 鼠标换着用

### 根因(已确认)

接收器一个 HID++ 接口转发所有 6 个 slot 的设备(报文 report[1] = deviceIndex 区分), 传输层无限制. 限制全在 Mos 的状态模型: 一个 LogiDeviceSession 只有一份 deviceIndex + 一份 featureIndex / divertedCIDs / discoveredControls / reprogInitComplete, 只建模了单个当前设备

- 启动自动锁定只在 finishPingPhase 发生, 它把目标锁到 connectedSlots.first(编号最小的在线 slot). 若键盘或另一只鼠标在更低号 slot, 目标锁错, 真正要用的鼠标 slot 从没被 target, 其按键不被 divert
- 补救路径也被堵: 后到的 0x41 device-connection 通知走 receiverConnectionNotificationAction, 那里 guard !currentTargetReady 会在当前目标已 ready 时直接 ignore, 永不 retarget
- 手动点 slot 时 outlineViewClicked 无条件 setTargetSlot + rediscoverFeatures, 绕过一切强锁, 所以一点就好
- 单目标模型下, 两只鼠标换手无解: 追活跃鼠标需要信号, 但没被 divert 的鼠标不发 HID++ 按键事件, 移动又走另一条 HID 接口, app 无可靠信号感知切换

结论: 单目标 + prefer-mouse 只能救"键盘+一只鼠标", 救不了"多鼠标". 正解是真多设备并行

## 2. 性能红线(最重要, 不可违反)

历史上做过一次相关的性能/稳定性修复, 见:

- commit 2a573be "fix(logi): stabilize BLE button handling"
- docs/plans/2026-05-03-logi-ble-hidpp-divert-postmortem.md 第 4.2 节

当时试过用 IRoot.Ping / Get/SetControlReporting 的 pulse + 多轮探针去维持 HID++ 通知流, 结论是移除: 只能短暂唤醒、和 Logi Options+ 抢 HID++ ownership、增加设备负担和状态振荡. 原文处理: "已移除 HID++ notification watchdog / pulse / protocol probe matrix, 不再把 keepalive 作为产品修复策略"

红线约束(本重构必须全程满足):

- 不得新增任何周期性 / 重复的 HID++ 活动: 无 watchdog, 无 pulse, 无 keepalive, 无轮询定时器
- 每个设备的 discovery + divert 只在其连接时做一次(one-shot), 之后安静监听
- 不得对每个 0x41 都 retarget / 重发现, 所有 retarget / 收敛动作加"已完成"守卫, 防状态振荡
- reporting 刷新(冲突图标)沿用既有节流(refreshReportingStates, 10s / 30s 最小间隔 + skip-when-in-flight), 不加密
- 多设备只是把"一次性 discovery+divert"从 1 个设备扩到 N 个设备; 它本身不引入周期动作, 与被删掉的 keepalive 是两回事

判定标准: 若某改动会随时间反复发 HID++ 请求, 就是踩线; 若只在连接 / 断开 / 用户操作等离散事件上各做一次, 就是安全的

## 3. 关键代码地图(现状)

全部在 Mos/Logi/Core/LogiDeviceSession.swift, 除非另注. 行号为撰写时的近似值, 执行时以符号搜索为准

| 符号 / 位置 | 作用 | 备注 |
|---|---|---|
| deviceIndex (var, ~97) | 当前单一目标 slot | 待改: 概念拆成"巡检游标" vs"接管集合" |
| featureIndex (var, ~94) | featureId to index 映射 | 待改: 按 slot 拆 |
| divertedCIDs (var, ~95) | 已 divert 的 CID 集 | 待改: 按 slot 拆 |
| discoveredControls (var, ~126) | 已发现控件列表 | 待改: 按 slot 拆 |
| reprogInitComplete (var, ~127) | 该目标 reprog init 是否完成 | 待改: 按 slot 拆 |
| setup() (~853-912) | 判定 connectionMode; receiver 设 deviceIndex=0x01 临时值, 调 enumerateReceiverDevices; BLE 直接 startFreshDiscovery | receiver 分支是入口 |
| enumerateReceiverDevices() (~1399-1422) | ping slot 1-6, 5s 一次性超时 | 一次性, 无 timer 循环 |
| pingReceiverSlot(slot) (~1425-1450) | 发 IRoot.Ping 短报文 | |
| handleSlotPingResponse (~1539) | ping 成功 -> isConnected=true | |
| finishPingPhase() (~1563-1594) | ping 阶段结束: 对在线 slot queryReceiverDeviceInfo, 锁 connectedSlots.first, startFreshDiscovery, handshakeComplete=true | 主 bug 点: 锁最低号 |
| queryReceiverDeviceInfo(slot) (~1453) | 读接收器寄存器 0xB5 (pairingInfoDeviceInfo 0x20) | 异步 |
| handleReceiverRegisterResponse (~1597-1612) | 解析 device info: report[10]=deviceType, report[8-9]=wirelessPID | deviceType 0x02=Mouse |
| ReceiverPairedDevice (struct, ~163) | slot 的 isConnected / deviceType / wirelessPID / name | 已有类型信息 |
| setTargetSlot(slot) (~1373-1394) | 只设 deviceIndex + 清状态, 不起 discovery | 需配 rediscoverFeatures |
| rediscoverFeatures() (~1291) | 清状态 + startFreshDiscovery | |
| startFreshDiscovery (~1011) | 发现 0x1B04 -> GetControlCount -> ControlInfo 循环 | reprog 链入口 |
| divertBoundControls() (~3439) | reconcile + reprogInitComplete=true + primeFromRegistry(下发 divert) + probeOptionalFeatures | reprog 链终点 |
| handleDeviceConnectionNotification (~1629-1676) | 处理 0x41; 调 receiverConnectionNotificationAction 决策 | |
| receiverConnectionNotificationAction (static, ~785-802) | 纯函数 gate: ignore / currentTargetConnected / currentTargetDisconnected / retarget | 已有单测 |
| currentReceiverTargetIsConnected (~734, static ~760) | 当前目标 slot 是否在线, 门控 divert/按键管线 | |
| handleInputReport (dispatch) | 0x41 (~2837), IRoot handleDiscoveryResponse (~2711), reprog (~2726), haptic/scrollforce/forcesensing 各 feature 块 | 待改: 按 report[1] 分发 |
| handleDiscoveryResponse (~2977) | 用 pendingDiscovery.first 匹配 IRoot 响应 | 关键约束: 见 3.1 |
| 出站 report[1] = deviceIndex (~974, ~989) | sendRequest 目标编码 | 多设备时按目标 slot 设 |
| outlineViewClicked (LogiDebugPanel.swift ~816-841) | slot 点击 -> setTargetSlot + rediscoverFeatures | 巡检游标语义 |

### 3.1 IRoot 发现响应的串行约束(必读)

IRoot getFeature 的响应不携带被查询的 featureId, handleDiscoveryResponse 靠 pendingDiscovery.first 匹配唯一在飞项. 因此同一时刻只能有一个 discoverFeature 在飞, 否则 index 张冠李戴. 本会话刚把 haptic/scrollForce/forceSensing/扩展功能的探测统一成一条串行链 probeOptionalFeatures 就是为此(见 LogiDeviceSession.swift 内 optionalProbeFeatures / probeOptionalFeatures / probeNextOptionalFeature)

多设备实现必须遵守: 跨 slot 的 feature 发现也要串行(slot A 的发现完成后再发 slot B 的), 不能并发. 建议做一个全局(session 级)的发现队列, 串行处理所有 slot 的所有发现请求

## 4. 目标架构

### 4.1 两个概念解耦

- 接管集合(button divert set): 所有"已连接 + 是鼠标 + Mos 有绑定"的 slot. 这些 slot 各自跑一次 discovery + divert, 常驻接管. 与 debug 面板无关, app 启动即生效
- 巡检游标(inspection cursor): 就是现在的 deviceIndex, 只服务 debug 面板"我现在在看哪个 slot 的 features". 面板点 slot 只改这个游标, 不影响接管集合

### 4.2 每 slot 状态(核心)

把下列单值状态按 slot(UInt8 1-6)拆成字典 / 结构数组:

- featureIndex: [slot: [UInt16: UInt8]]
- discoveredControls: [slot: [ControlInfo]]
- divertedCIDs: [slot: Set<UInt16>]
- reprogInitComplete: [slot: Bool]
- reprog 发现游标(reprogControlCount / reprogQueryIndex / reportingQueryIndex / controlInfoRetryCounts 等): 按 slot
- lastApplied 等 divert 对账缓存: 按 slot

建议做一个 PerSlotState 结构体聚合这些, 用 [slot: PerSlotState] 持有, 减少散落字典

### 4.3 巡检专用状态(可不拆, 保持单值)

haptic / scrollForce / forceSensing 的缓存状态 + optionalProbe 探测守卫是 debug 面板巡检用的手动工具, 只需服务当前巡检游标那个 slot, 不进入常驻按键管线. 保持单值, 绑定到 deviceIndex 即可; 切换巡检 slot 时 reset(现有 resetHaptic/ScrollForce/ForceSensing/OptionalProbe 已在 setTargetSlot 调用). featureIndex 因为被 reprog 和巡检都用, 按 slot 拆后, 巡检读 featureIndex[deviceIndex]

### 4.4 报文分发

handleInputReport 目前隐式单目标. 改为: 先取 slot = report[1](receiver 模式), 用该 slot 的 PerSlotState 路由 reprog / 发现 / diverted-button-event. 注意:

- 只有 receiver 模式需要按 slot 分发; bleDirect(deviceIndex=0xFF)和 unsupported 不变
- diverted button event -> 按 slot 找到该设备的 wirelessPID -> 查该设备的绑定集执行(见 4.5)
- 0x41 / 寄存器响应 / ping 响应等接收器级报文不按 slot 分发(它们本就带 slot 字段各自处理)

### 4.5 绑定路由(同型号 vs 不同型号统一处理)

按键事件要执行正确的绑定. 通用方案: slot -> wirelessPID(已在 ReceiverPairedDevice) -> 查该 productId 的绑定集. 同型号两只鼠标 wirelessPID 相同, 自然共用同一套绑定; 不同型号各自的绑定集, 也自然分开. 无需区分同异型号

执行时需先核实绑定注册表怎么按设备键控(见 6.4 Phase 3 调研项): 确认 primeFromRegistry / ButtonBinding registry 是按 productId 还是全局. featureIndex 缓存已是按 productId(saveCachedFeatureIndex / loadCachedFeatureIndex), 说明 productId 维度已存在, 路由可复用

### 4.6 接管集合的确定(哪些 slot 要 divert)

启动枚举 + device-info 回来后, 对每个"isConnected 且 deviceType==Mouse 且 Mos 有该 wirelessPID 绑定"的 slot 各起一次 discovery+divert. 加"绑定过滤"是性能考虑: 不给用户没绑定的设备做 divert, 避免无谓 HID++ 负载与 Options+ 争用. 若担心"用户新绑一个设备后不重连不生效", 在绑定变更事件上补一次该 slot 的 divert(离散事件, 一次性, 不违红线)

## 5. 纯函数(优先实现 + 单测, 无需硬件)

抽出可单测的纯决策函数, 与 IO 解耦:

1. chooseReceiverTargetSlot(devices: [ReceiverPairedDevice]) -> UInt8?
   巡检游标默认选择: 优先 deviceType==Mouse 的在线 slot, 无鼠标回退首个在线, 全空 nil. 用于 finishPingPhase 的默认巡检游标(不再锁最低号)

2. receiverDivertSlots(devices: [ReceiverPairedDevice], hasBinding: (UInt16) -> Bool) -> [UInt8]
   接管集合: 过滤 isConnected && deviceType==Mouse && hasBinding(wirelessPID). 决定给哪些 slot 起 divert

3. receiverConnectionNotificationAction 扩展(已有单测 MosTests/LogiReceiverConnectionStateTests.swift)
   现签名判定单目标 retarget. 多设备下语义变为: 某 slot 的 0x41(connected)-> 若该 slot 属于接管集合且尚未 init -> 起该 slot 的一次 discovery+divert; disconnected -> 释放该 slot 的按键状态 + 标记未 init. 不再有"抢占式 retarget", 因此 currentTargetReady / retarget 到别的 slot 的旧语义可移除或改为 per-slot 的"该 slot 是否需要 (re)init". 用纯函数表达"收到某 slot 的 0x41 该做什么", 加"该 slot 已 init 且在线则忽略"守卫防振荡

4. report 分发的 slot 提取 + 路由判定(可抽纯函数: 给定 report[1] 与已知接管 slot 集, 返回应路由到哪个 slot 或 ignore)

## 6. 分阶段实现(每阶段可编译 + 可测 + 尽量可单独验证)

强烈建议严格分阶段, 每阶段结束都编译 + 跑单测 + 提交. 这是核心状态模型重构, 一次性大改风险高

### Phase 0 — prefer-mouse 巡检游标(小,先落地, 也是回退基线)

- 加纯函数 chooseReceiverTargetSlot + 单测
- finishPingPhase 的默认巡检游标从 connectedSlots.first 改为 chooseReceiverTargetSlot(devices), 且推迟到 device-info 到齐后选一次(串行约束: device-info 是寄存器读, 与 IRoot 发现不同, 可并发, 但目标选择要等类型齐). 类型始终不回则回退首个在线(不退化)
- 效果: 单鼠标 + 键盘场景立即修复; 多鼠标仍只巡检一只(Phase 2 才真并行)
- 不改按键管线, 风险低

### Phase 1 — 每 slot 状态容器(机械重构, 行为不变)

- 引入 PerSlotState 结构 + [slot: PerSlotState] 持有
- 把 featureIndex / discoveredControls / divertedCIDs / reprogInitComplete / reprog 游标迁移进去
- 现有单目标代码全部改成 read/write slotState(deviceIndex)(即"当前巡检 slot"), 行为与现在完全一致
- 目的: 把大改拆成"先建容器不改行为", 再"扩到多 slot", 降低风险
- 编译 + 全量单测通过 + 手测 BLE 与单设备 receiver 行为不变

### Phase 2 — 多 slot discovery + divert + 报文分发(核心)

- 启动收敛后, 对 receiverDivertSlots 返回的每个 slot 各起一次 discovery+divert(串行发现队列, 遵守 3.1)
- handleInputReport 按 report[1] 路由到对应 slotState(见 4.4)
- 出站 sendRequest 的 report[1] 按当前处理的目标 slot 设(注意区分: 巡检发的请求用巡检 slot, 接管 divert 发的请求用各自 slot)
- currentReceiverTargetIsConnected 等门控从"单目标在线"改为"该 slot 在线"
- 单测: report 分发路由; receiverDivertSlots
- 手测: 两只鼠标都插在接收器, app 启动后两只的 HID++ 按键都可用

### Phase 3 — 绑定路由 + 巡检游标解耦

- diverted button event -> slot -> wirelessPID -> 该设备绑定集执行(先做 6.4 调研)
- 面板 slot 点击只改巡检游标, 不再驱动按键接管(接管已在 Phase 2 常驻)
- 巡检 UI(features 表 / haptic 等 context)读 slotState(巡检游标)

### Phase 4 — 热插拔 / 0x41 多设备语义

- 某鼠标后连接(0x41 connected)-> 若属接管集合且未 init -> 起该 slot 一次 discovery+divert
- 某鼠标断开(0x41 disconnected)-> 释放该 slot 按键状态 + 标记未 init, 不清别的 slot
- 全部一次性 / 离散事件驱动, 加"已 init 且在线则忽略"守卫防振荡
- 单测扩 receiverConnectionNotificationAction(或其多设备后继)

### 可选 Phase 5 — 启用无线通知寄存器写(仅在实测发现"已连接设备不发 0x41"才做)

- 现在没有任何寄存器 SET(只有 0x81/0x83 GET). 若实测发现某些已连接设备启动后不发 0x41 导致 Phase 4 收不到信号, 再考虑连接时写一次寄存器 0x00 开无线通知(一次性写, 非 keepalive, 不违红线)
- 默认不做, 因为启动 ping 枚举已能发现在线 slot; 仅作兜底

## 7. 测试策略与操作陷阱(执行者必读)

### 7.1 单测优先纯函数

本仓库惯例: 协议解析 / 决策逻辑抽成纯函数 + 静态 ...ForTests 包装 + XCTest. 参考已有:
- MosTests/LogiReceiverConnectionStateTests.swift(receiverConnectionNotificationAction)
- MosTests/LogiScrollForceTests.swift / LogiForceSensingTests.swift(feature 解析, 本会话新增, 可作模板)
测试 target 模块名 Mos_Debug, 文件头 `@testable import Mos_Debug`

### 7.2 新测试文件必须手动加进 pbxproj(重要)

MosTests 不是 Xcode 同步组(同步组只覆盖 Mos/ 目录), 用的是显式文件引用. 新建的 .swift 测试文件不会自动进 target. 必须在 Mos.xcodeproj/project.pbxproj 手动加 4 处(用一对新的唯一 UUID, 参照 LogiScrollForceTests 的 D1A2B3C4E5F6A7B8C9D01700/01701 与 LogiForceSensingTests 的 ...01800/01801 递增):
1. PBXBuildFile 段
2. PBXFileReference 段
3. 该 group 的 children 列表
4. Sources build phase 的 files 列表
漏任何一处都会导致"No such module XCTest"或测试不被编译

### 7.3 跑测试的坑

- 存在两个同名 "Debug" scheme: 共享 scheme(Mos.xcodeproj/xcshareddata/xcschemes/Debug.xcscheme, 有 TestAction)被 xcuserdata 里的用户 scheme(空 TestAction)遮蔽. xcodebuild -scheme Debug 会解析到用户 scheme 报 "not configured for the test action"
- 解法: 临时把 Mos.xcodeproj/xcuserdata/Caldis.xcuserdatad/xcschemes/Debug.xcscheme 移走, 跑完再移回(务必保证还原)
- 测试 bundle 加载会因宿主 app 与测试 bundle 的签名 Team ID 不一致而失败. 跑测试加 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
- 完整命令模板:

```
US="Mos.xcodeproj/xcuserdata/Caldis.xcuserdatad/xcschemes/Debug.xcscheme"
BK="$US.bak"; mv "$US" "$BK"; trap 'mv "$BK" "$US" 2>/dev/null' EXIT
xcodebuild test -scheme "Debug" -destination 'platform=macOS' -configuration Debug \
  -only-testing:MosTests/LogiReceiverConnectionStateTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 \
  | grep -iE "Executed .* test|TEST (SUCCEEDED|FAILED)| error:"
mv "$BK" "$US" 2>/dev/null; trap - EXIT
```

### 7.4 编译验证

```
xcodebuild build -scheme "Debug" -destination 'platform=macOS' -configuration Debug 2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED"
```

- SourceKit 那种 "Cannot find type 'LogiDeviceSession' in scope" 的诊断是跨文件索引噪声, 以 xcodebuild 实际结果为准
- 注意: xcodebuild build 可能触发 Xcode 自动迁移 Mos/Base.lproj/Main.storyboard(toolsVersion 升版 + 批量删 focusRingType). 提交前 git diff 检查, 别把这类无关 churn 混进提交

### 7.5 集成验证(无双鼠标环境时)

纯函数全单测覆盖. 集成路径靠面板 PROTOCOL LOG: 在关键点加 LogiDebugPanel.log, 连接时应能看到每个接管 slot 各自的 "Auto-diverting slot N (Mouse pid=0x...)" 与 "slot N init complete", 用户可据此确认两只都被接管. 执行者本机若无双鼠标接收器, 交付时明确标注"集成路径未在真机验证, 需用户在双鼠标环境确认"

## 8. 风险与注意

- 这是 session 核心状态模型重构, 面大. 严格分阶段 + 每阶段编译/单测/提交是控制风险的关键
- BLE 直连路径(deviceIndex=0xFF)与 unsupported 路径不得回归; 每阶段手测这两条
- 接收器上的键盘不进接管集合(deviceType!=Mouse), 避免给 Mos 不管的设备做 divert
- 严守第 2 节红线: 任何"反复发 HID++ 请求"的实现都是错的
- 单接收器单设备(最常见)行为必须与现在完全一致, 不能因多设备改动变慢或变化

## 9. 需要执行者先确认 / 调研的开放项

1. 6.4: 绑定注册表(primeFromRegistry / ButtonBinding registry)如何按设备键控 — 是 productId 还是全局. 决定 4.5 路由实现. 先读 Divert 相关代码(Mos/Logi/Divert/ 与 primeFromRegistry 调用链)
2. 出站请求在多 slot 下的目标 slot 归属: 巡检请求 vs 接管 divert 请求分别用哪个 slot 作 report[1]
3. Phase 5 是否需要, 取决于 Phase 4 实测某设备是否收不到 0x41

## 10. 本次会话已完成 / 相关背景(避免重复劳动)

- 刚合入 master 的三个提交(与本重构相邻, 不冲突): 86e5844 Scroll Force(0x2111), 8ecd9a2 修 Event Monitor 崩溃, abd4004 批量扩展可选功能 + 探测串行化
- abd4004 引入了 probeOptionalFeatures 串行探测链, 正是 3.1 串行约束的现成范例, 多设备发现队列可参考其写法
- haptic/scrollForce/forceSensing 三个 bespoke context 是巡检工具, 按 4.3 保持单值即可, 不必进多设备管线
