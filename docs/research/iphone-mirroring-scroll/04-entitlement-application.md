# Entitlement 申请记录

## 2026-07 DriverKit Entitlement 请求 (已结案)
- **Request ID: `7CTL26535S`**(跟进时引用)
- 提交账号邮箱: cn@caldis.me / Team: BIAO CHEN – N7Z52F27XK
- Company/Product URL: https://github.com/Caldis/Mos
- 勾选(申请表,粒度粗): **HID** + **UserClient Access**
- UserClient Bundle IDs: `com.caldis.Mos.driver`
- 描述要点: 开源可审计 + 发布单个虚拟 HID 定位设备 + App 经 user client 驱动它 + 因某些系统组件(如 iPhone 镜像)在 CGEvent 层之下读输入,故需虚拟 HID 让用户偏好一致生效 + 用户自有输入、opt-in、不采集不针对其它应用。

## 审批结果 (2026-09)
- DriverKit 申请 7CTL26535S 被拒 (Transport HID, HID EventService, Family HID Device, UserClient Access, DriverKit), dext 路线只能用于本机开发
- HID Virtual Device (com.apple.developer.hid.virtual.device) 于 2026-09-15 下发到开发者账号, 分发类型含 Development 与 Developer ID
- 启用方式: Xcode 目标的 Signing & Capabilities 中添加 HID Virtual Device, 或在开发者网站 Identifiers 的 Capabilities 页勾选; 命令行构建不会自动启用
- 2026-09-30 复测使用 App ID `com.mos.vhidprobe`. 同日曾在 `com.caldis.Mos` 中试启用, 该次试验的本地 entitlements 随后撤回
- PR #1045 合入 Mos 的 HID Virtual Device 签名配置. 普通 Debug 构建使用空 entitlement, 受限能力构建需要对应 Apple 授权和描述文件. [当前签名配置](../../../Config/MosDebug.xcconfig) · [适配器方案](../../plans/2026-10-12-iphone-mirroring-scroll.md)

## 标识符(App ID)配置
为过申请表的 bundle id 校验,注册了 explicit App ID **`com.caldis.Mos.driver`**,并在其能力页启用 DriverKit **(development)** 系列。dext 需要的完整集合(对齐 Karabiner):
- `DriverKit` + `Family HID Device` + `Family HID EventService` + `Transport HID` + `Allow Any UserClient`
> 三处 bundle id 必须逐字一致:申请表 UserClient Bundle IDs / 此 App ID / 将来 Xcode dext target 的 CFBundleIdentifier。
> 标识符能力页(development,自助、可随时改)与申请表(distribution,人工审)是**两套独立系统**,粒度不同,不需一一对应。

## 概念澄清:三类 entitlement
| entitlement | 类别 | 能否第三方获取 | 用途 |
|---|---|---|---|
| `com.apple.private.hid.client.event-dispatch` | `private` | ❌ 只发 Apple 自家 | 直接向 IOHIDEventSystem 注入(我们**不需要**也拿不到) |
| `com.apple.developer.driverkit.*` / `family.hid.*` | `developer` | 分发申请被拒 | DriverKit 备选方案 |
| `com.apple.developer.hid.virtual.device` | `developer` | 已获受管能力 | CoreHID 原型与 Mos 的设备身份 |

7 月自动签名失败记录涵盖当时的 Xcode 26.0 与尚未获批的账号. 9 月复测使用 Xcode 26.3 和包含 HID Virtual Device 能力的描述文件. [签名诊断与复测](03-experiment-log.md)
