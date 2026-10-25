# 权限生命周期与欢迎页实施计划

读者: Mos 开发者与后续 agent

## 实施范围

1. 增加独立权限采样和监听释放门控, 回归覆盖撤权、过期采样、恢复及重复释放
2. 修正 Interceptor 资源生命周期与 KeyRecorder 取消流程, 统一 AppDelegate 权限状态
3. 使用纯 AppKit 欢迎窗口与 Metal 图标动画, 保留原有授权语义
4. 独立 bundle 接入 PermissionFlow 2.11.4 与 Vortex 1.0.4, 主应用最低系统版本保持 macOS 10.13
5. 使用 Debug scheme 执行相关 MosTests 和构建, 通过独立预览模式截图验收

## 设计决策

Chromium 修复 7474294381a3b199f2ecc66ed892c1e48ee1f970 记录了撤权后 AXIsProcessTrusted 返回陈旧状态的问题, IOHIDCheckAccess 的 PostEvent 检查能区分拒绝和移除状态. 本次 Mos 事故缺少 callback 日志, 上游证据只支持防御方案, 具体事故归因仍待验证

权限采样在工作队列执行. 输入资源的释放独立于主线程和 run-loop 模式. 采样超时采用失效关闭, UI 清理回到主线程. 权限恢复使用新 tap 实例

PermissionFlow 原版要求 macOS 13, 独立 bundle 仅在兼容系统加载. 旧系统使用原生授权提示. Vortex 庆祝使用透明、点击穿透窗口, 窗口关闭、Reduce Motion 和定时结束均释放资源

## 验证边界

自动测试使用注入权限状态与资源替身. 主力 Mac 保持当前系统权限. 预览模式跳过输入核心、设备初始化和权限操作. 真实撤权与旧版系统运行结果单独记录

## 验证记录

- 本次检出分支: `research/iphone-mirroring-scroll`
- 用户原有 `project.pbxproj` 中 DGCharts 名称修正保留
- 已安装应用回读: 4.3.0 / 20260820.1; 本次构建产物位于 `/tmp/mos-onboarding-build`
- 门控回归: 初始实现的撤权释放与查询过期用例失败, 修复后通过
- 并发回归: 资源销毁期间的放行状态读取用例先因锁阻塞超时, 清理操作移出锁后通过
- 热键回归: 停用时按住状态清理用例先失败, 修复后通过
- Debug build 与 85 项定向测试通过, 覆盖权限释放、恢复、录制取消、创建失败、热键释放、欢迎状态、bundle 加载与庆祝窗口清理
- Logi 边界检查与 `git diff --check` 通过
- 新增权限与欢迎页代码通过 `x86_64-apple-macosx10.13` 的独立 availability 类型检查; 外围应用类型使用测试桩, 该结果只覆盖本次新增文件的 API 可用性
- 中文深色、英文浅色、Logo 描边与光效填充阶段完成实际截图检查, 文字位置保持稳定
- 安全预览点击授权按钮后, 系统设置打开对应权限页; 原版浮窗的完整跟随和拖放仍待人工验收

## PR 分支验证

- PR 分支: `codex/accessibility-recovery-onboarding`, 基线为 master 的 `8a2fd11`
- 保留 master 的 Interceptor 自动重启冷却机制, AppDelegate 使用 master 的输入服务集合
- Debug build 与 89 项定向测试通过, 包含 InterceptorAutoRestartTests 的 5 项回归
- 命令行使用 `MACOSX_DEPLOYMENT_TARGET=13.0`, Logi 边界检查与 `git diff --cached --check` 通过

## 工具链与运行边界

当前机器使用 Xcode 27.0. 常规 10.13 构建首先触发 deployment target 错误; 临时降低诊断级别后, 现有 LoginServiceKit 模块仍以 macOS 12 编译, 主应用导入失败. 本次可执行 build/test 仅在命令行指定 `MACOSX_DEPLOYMENT_TARGET=13.0`, 仓库主应用配置仍为 10.13

输入事件的真实撤权复现、授权恢复后的真实键鼠输入、10.13 系统运行以及真实设备测试均留待隔离环境验证. 本次安全预览跳过输入核心、设备初始化和权限采样, 使用模拟授权状态验证成功界面. 系统权限维持原状, 安装版保持原状, PR 分支基于 master 的 `8a2fd11` 提取本次改动, 原研究分支与工作区保留

## 参考

- [Chromium 运行中撤权修复](https://chromium.googlesource.com/chromium/src/+/7474294381a3b199f2ecc66ed892c1e48ee1f970)
- [PermissionFlow v2.11.4](https://github.com/jaywcjlove/PermissionFlow/tree/v2.11.4)
- [Vortex 1.0.4](https://github.com/twostraws/Vortex/tree/1.0.4)
