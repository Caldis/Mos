# Entitlement 申请记录

## 已提交:DriverKit Entitlement 请求
- **Request ID: `7CTL26535S`**(跟进时引用)
- 提交账号邮箱: cn@caldis.me / Team: BIAO CHEN – N7Z52F27XK
- Company/Product URL: https://github.com/Caldis/Mos
- 勾选(申请表,粒度粗): **HID** + **UserClient Access**
- UserClient Bundle IDs: `com.caldis.Mos.driver`
- 描述要点: 开源可审计 + 发布单个虚拟 HID 定位设备 + App 经 user client 驱动它 + 因某些系统组件(如 iPhone 镜像)在 CGEvent 层之下读输入,故需虚拟 HID 让用户偏好一致生效 + 用户自有输入、opt-in、不采集不针对其它应用。

### 跟进方式(无后台状态页)
- 结果走邮件到 cn@caldis.me(**查垃圾箱/推广箱**,加白 `@apple.com`)。
- 时间: 常见 2–4 周,也可能更久/无回音。
- 催办(带 Request ID 7CTL26535S): [developer.apple.com/contact](https://developer.apple.com/contact/) → Membership & Account;或开 DTS 工单(最有效);或回复 Apple 邮件。

## 标识符(App ID)配置
为过申请表的 bundle id 校验,注册了 explicit App ID **`com.caldis.Mos.driver`**,并在其能力页启用 DriverKit **(development)** 系列。dext 需要的完整集合(对齐 Karabiner):
- `DriverKit` + `Family HID Device` + `Family HID EventService` + `Transport HID` + `Allow Any UserClient`
> 三处 bundle id 必须逐字一致:申请表 UserClient Bundle IDs / 此 App ID / 将来 Xcode dext target 的 CFBundleIdentifier。
> 标识符能力页(development,自助、可随时改)与申请表(distribution,人工审)是**两套独立系统**,粒度不同,不需一一对应。

## 概念澄清:三类 entitlement
| entitlement | 类别 | 能否第三方获取 | 用途 |
|---|---|---|---|
| `com.apple.private.hid.client.event-dispatch` | `private` | ❌ 只发 Apple 自家 | 直接向 IOHIDEventSystem 注入(我们**不需要**也拿不到) |
| `com.apple.developer.driverkit.*` / `family.hid.*` | `developer` | ✅ 需申请(已提交) | DriverKit 路线 B |
| `com.apple.developer.hid.virtual.device` | `developer` | ✅ 门控 | CoreHID 路线 B(**本轮选定**) |

## 待办
- CoreHID 路线用的是 `com.apple.developer.hid.virtual.device`,**与已提交的 DriverKit 申请不是同一个**。若 CoreHID 原型验证需要它而其分发授权也需单独申请,再评估是否补交。开发验证阶段:development 签名 + 该能力若可自助勾选则无需审批(见实验 README「签名」)。
