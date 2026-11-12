# Code Map

本文件给 agent 一个快速地图。它不是架构设计文档；真正的行为仍以源码和测试为准。

## 主要模块

- `Mos/ScrollCore/`：滚动事件捕获、过滤、插值和平滑派发。属于热路径，改动时关注分配、日志、通知和线程语义。
- `Mos/ButtonCore/`：鼠标按键事件处理、动作映射和输入处理。
- `Mos/InputEvent/`：统一输入事件模型，是 ButtonCore、Shortcut、KeyRecorder 等模块之间的边界类型。
- `Mos/Shortcut/`：系统快捷键定义和动作执行。
- `Mos/Keys/`：快捷键和鼠标按键录制 UI 与数据结构。
- `Mos/Logi/`：Logi/HID++ 集成、设备会话、功能注册、divert、usage registry 和 debug 工具。
- `Mos/Integration/`：Logi 与应用其他层之间的桥接边界。
- `Mos/Managers/`：窗口、状态栏、快捷键等应用级单例管理器。
- `Mos/Options/`：UserDefaults 配置、应用例外规则和持久化模型。
- `Mos/Components/`：可复用 UI 组件，包含 Toast。
- `Mos/Windows/`：欢迎、介绍、偏好设置和监视器窗口。
- `MosTests/`：XCTest 测试；`MosTests/LogiTestDoubles/` 存放 Logi 测试替身。

## 仓库支持目录

- `assets/readme/`：README 展示图片和归档截图。
- `assets/source/app/`：App 视觉源素材和历史导出，不会直接进入 app bundle；运行时资源应导入 `Mos/Assets.xcassets`。
- `packaging/dmg/`：DMG 构建脚本、构建输入和历史 DMG 设计素材。
- `release/`：Sparkle appcast 和公开 release notes 源文件。
- `scripts/`：可重复执行的项目自动化脚本。
- `tools/`：手动运行的诊断、探测和回归 harness。

## 边界约定

ScrollCore 是滚动热路径。不要在高频路径中加入不必要的对象分配、同步 I/O、日志、通知或跨模块调用, 性能是优先事项。

ButtonCore、InputEvent、Shortcut 和 Keys 共同处理按键录制、菜单展示、持久化和动作执行。修改其中一个模块时，要检查其他模块是否仍保持同一套语义。

Logitech 的细节应留在 `Mos/Logi/`。应用其他层通过 `LogiCenter`、`Mos/Integration/` 或明确 facade 访问，避免 HID++ packet、device session、divert 细节扩散到窗口层或 ButtonCore。

`Mos/Integration/` 可以知道更多 Logi bridge 类型，但普通应用层只能使用公开 allowlist。相关改动跑：

```bash
scripts/qa/lint-logi-boundary.sh
```

## 持久化和兼容性

涉及以下内容时要格外谨慎，并优先补 canary 或兼容测试：

- `UserDefaults` key。
- 快捷键、动作、category、shortcut identifier。
- Logi cache、feature、CID、usage registry 相关常量。
- Storyboard object id 和 `.xcstrings` key。
- Sparkle `CURRENT_PROJECT_VERSION`。

## Xcode 工程

新增、移动或删除 Swift 文件后，要确认 `Mos.xcodeproj/project.pbxproj` 里的 target membership 与文件位置一致。只创建文件不代表它会被编译或测试。
