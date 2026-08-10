# [4.2.0](https://github.com/Caldis/Mos/releases/tag/4.2.0)

## 新功能
- 新增 Logi/HID++ 原生支持, 可识别 Bolt/Unifying 接收器与蓝牙直连设备按钮, 并支持分配 Logi 专有事件。
  - 相关协议参考了大量项目的逆向工程, 感谢 [Solaar](https://github.com/pwr-Solaar/Solaar) 等项目的开源。
- 按钮绑定新增「打开…」动作, 可启动 App、运行脚本或打开任意文件, 支持拖拽选择与启动参数。
- 按钮绑定新增「自定义…」录制, 可更灵活地处理鼠标按键动作。
- 滚动功能现在支持绑定任意自定义按键。

## 优化
- 新增捷克语本地化, 感谢 @karelfh。

## 修复
- 修复滚动选项等值比较方向错误, 感谢 @seng1e。
- 修复辅助功能权限在运行中被撤销后, 可能阻断系统输入的问题。
- 修复按键映射功能导致在部分应用中左键点击异常的问题: https://github.com/Caldis/Mos/issues/890
- 改进 DisplayLink 异常和屏幕变化后的平滑滚动恢复路径, 降低滚动异常或卡住的风险。
- 修复自定义按键录制、纯修饰键显示、同时松开修饰键识别和录制期间误触发动作的问题。

---

## New
- Added native Logi/HID++ support for Bolt/Unifying receivers and Bluetooth direct-connected device buttons, with support for assigning Logi-specific events.
  - The related protocol work references reverse engineering from many projects; thanks to open-source projects such as [Solaar](https://github.com/pwr-Solaar/Solaar).
- Added an "Open..." button action to launch apps, run scripts, or open any file, with drag-and-drop selection and launch arguments.
- Added "Custom..." recording for button bindings, enabling more flexible mouse button actions.
- Scroll features can now be bound to any custom key.

## Improvements
- Added Czech localization, thanks @karelfh.

## Fixes
- Fixed reversed scroll options equality comparison, thanks @seng1e.
- Fixed system input blocking when Accessibility permission is revoked while Mos is running.
- Fixed abnormal left-click behavior in some apps caused by button mapping: https://github.com/Caldis/Mos/issues/890
- Improved smooth-scroll recovery after DisplayLink errors and screen changes, reducing the risk of abnormal or stuck scrolling.
- Fixed custom key recording, pure modifier display, simultaneous modifier release detection, and accidental action execution while recording.

# [4.0.2](https://github.com/Caldis/Mos/releases/tag/4.0.2)

## 修复
- 进一步尝试修复平滑滚动导致的崩溃问题。感谢 #868, #826, #699, #687, #665, #510, #512, #499, #368, #597, #859 提供的日志。

---

## Fixes
- Further attempted to fix crashes caused by smooth scrolling. Thanks to #868, #826, #699, #687, #665, #510, #512, #499, #368, #597, and #859 for the logs.

# [4.0.1](https://github.com/Caldis/Mos/releases/tag/4.0.1)

## 新功能
- 添加 UU 远程桌面支持, 防止主机与客户端同时安装 Mos 时出现双重平滑问题, 感谢 @jijiamoer (#879)。

## 修复
- 修复滚动事件派发问题, 引入 ScrollDispatchContext 重构 ScrollPoster, 解决部分场景下滚动异常 (#868, #826)。
- 修复 macOS 26+ 上 LaunchPad 检测逻辑, 避免影响 Dock 文件夹弹出视图, 感谢 @Lezheng2333 反馈 (#878)。

---

## New
- Added UU Remote Desktop support to prevent double-smoothing when both host and client have Mos installed, thanks @jijiamoer (#879).

## Fixes
- Fixed scroll event dispatching by introducing ScrollDispatchContext and refactoring ScrollPoster, resolving scroll anomalies in certain scenarios (#868, #826).
- Fixed LaunchPad detection on macOS 26+, avoiding interference with Dock folder popup views, thanks @Lezheng2333 for reporting (#878).

# [4.0.0](https://github.com/Caldis/Mos/releases/tag/4.0.0)

> 

## 新功能
- 全新加入「按钮」模块：现在可以直接将鼠标按键绑定到你想要的快捷动作。🎉
- 加入「模拟触控板」模式，我不知道有什么用, 但有点新鲜感总不是坏事 😜
- 现在可以在「滚动」中基于垂直、水平方向独立调味了

## 优化
- 欢迎指引、辅助功能授权流程 UI 翻新。
- 翻译迁移到 string catalogs, 再也不需要面对 identify string 了
- 基于 AI 补充了一些缺失的的多语言文本。(如果你觉得翻译有任何问题, 非常欢迎帮忙纠正!)

## 修复
- 修复部分场景下的滚动平滑滚动异常问题
- 修复欢迎指引、辅助功能授权流程中偶尔不同步的问题，希望你启动时能顺顺利利。

---

## New
- Brand-new Buttons module: record mouse and bind them to whatever shortcut you like. 🎉
- Added Simulate Trackpad mode. Unsure how useful it is yet, but it seems fun. 😜
- Vertical and horizontal scrolling can now be tuned independently inside the Scroll tab.

## Improvements
- Refreshed the welcome guide and accessibility permission in intro flow.
- Translations now power by string catalogs, no more identify strings.
- Filled a few missing translationg with a little help from AI. (If you find any problems with the translation, feel free to let us know!)

## Fixes
- Fixed the smooth scrolling issue in certain scenarios.
- Fixed the intro flow sync logic, so first launch might go more smoothly.

# [4.0.0-beta-20260201.1](https://github.com/Caldis/Mos/releases/tag/4.0.0-beta-20260201.1)

> 这是测试版本, 一些功能或内容可能会在正式版本中变更。

## 新功能
- 新增应用内更新检查（Sparkle），并支持可选的 Beta 渠道。
- 滚动功能键现在支持绑定任意热键。

## 改进
- 补充并修正部分本地化内容。

## 修复
- 修复部分非 US 键盘布局下的快捷键问题。
- 修复远程桌面或部分特殊设备的滚动输入无法被正确平滑的问题。

---

> This is a beta version. Some features or content may change in the official release.

## New Feature
- Added in-app update checking via Sparkle, with an optional beta channel toggle.
- Scrolling function keys can now be bound to any key.

## Improvements
- Refined localization strings.

## Fixes
- Fixed shortcut issues on non-US keyboard layouts.
- Fixed smooth scrolling not working properly with Remote Desktop or some special devices.

# [4.0.0-beta-1201](https://github.com/Caldis/Mos/releases/tag/4.0.0-beta-1201)

> 这是测试版本, 一些功能或内容可能会在正式版本中变更。

## 改进
- 为 4.0 版本更换了新的图标。
- 优化了状态栏图标尺寸。
- 更新了大咪照片。

---

> This is a beta version. Some features or content may change in the official release.

## Improvements
- Added a new icon for version 4.0.
- Optimized the status bar icon size.
- Updated photos of Meow.

# [4.0.0-beta-1105](https://github.com/Caldis/Mos/releases/tag/4.0.0-beta-1105)

> 这是测试版本, 一些功能或内容可能会在正式版本中变更。

## 优化
- 应用现在经过 Apple 公证, 不再会被提示为恶意软件了。
- 优化了日语文本校对, 感谢 @ulyssas。
- 优化了印尼语文本校对, 感谢 @harun-alrosyid。
- Website: 优化了波兰语和英文文本校对, 感谢 @MaciejkaG。

## 修复
- 修复最低系统版本被错误设置为 11.0 的问题, 现在依旧兼容 10.13。

---

> This is a beta version. Some features or content may change in the official release.

## Improvements
- App is now notarized by Apple and should no longer be flagged as malware.
- Improved Japanese text proofreading, thanks @ulyssas.
- Improved Indonesian text proofreading, thanks @harun-alrosyid.
- Website: improved Polish and English text proofreading, thanks @MaciejkaG.

## Fixes
- Fixed an issue where the minimum system version was incorrectly set to 11.0; Mos is still compatible with 10.13.

# [4.0.0-beta-1102](https://github.com/Caldis/Mos/releases/tag/4.0.0-beta-1102)

> 这是测试版本, 一些功能或内容可能会在正式版本中变更。

## 新功能
- 全新加入「按钮」模块：现在可以直接将鼠标按键绑定到你想要的快捷动作。🎉
- 加入「模拟触控板」模式，我不知道有什么用, 但有点新鲜感总不是坏事 😜
- 现在可以在「滚动」中基于垂直、水平方向独立调味了。

## 优化
- 欢迎指引、辅助功能授权流程 UI 翻新。
- 翻译迁移到 string catalogs, 再也不需要面对 identify string 了。
- 基于 AI 补充了一些缺失的多语言文本。(如果你觉得翻译有任何问题, 非常欢迎帮忙纠正!)

## 修复
- 修复 macOS 26 下的一些兼容性问题。
- 修复部分场景下的滚动平滑滚动异常问题。
- 修复欢迎指引、辅助功能授权流程中偶尔不同步的问题，希望你启动时能顺顺利利。

---

> This is a beta version. Some features or content may change in the official release.

## New
- Brand-new Buttons module: record mouse input and bind it to whatever shortcut you like. 🎉
- Added Simulate Trackpad mode. Unsure how useful it is yet, but it seems fun. 😜
- Vertical and horizontal scrolling can now be tuned independently inside the Scroll tab.

## Improvements
- Refreshed the welcome guide and accessibility permission intro flow.
- Translations are now powered by string catalogs.
- Filled a few missing translations with a little help from AI. If you find any problems with the translation, feel free to let us know.

## Fixes
- Fixed some compatibility issues on macOS 26.
- Fixed smooth scrolling issues in certain scenarios.
- Fixed the intro flow sync logic, so first launch should go more smoothly.

# [3.5.0](https://github.com/Caldis/Mos/releases/tag/3.5.0)

![IMG_8987](https://github.com/user-attachments/assets/55fac01c-d774-46f3-b118-6eebc50bdcc9)

> 由于 macOS 的安全性限制, 你需要允许 Mos 访问系统的辅助功能的访问权限以确保其正常运行

若 Mos 已在辅助功能的授权列表中, 只需取消勾选后再度勾选即可; 如果仍然无效, 请尝试将其从列表中移除再添加
可以在此处查看帮助: [无法正确获取辅助功能权限](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

> 如果在初次启动应用时被系统阻止, 你可以查看帮助: [如果应用无法正常运行](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

> [如果想看大咪点这里](https://meow.caldis.me)

## 新特性

- 希腊语支持, 感谢 @Valamorde 
- 乌克兰语支持, 感谢 @dittohead 
- 应用图标及状态栏图标更新

## 修正
 
- 在 Catalyst 应用中停止滚动后立即触发滚动无法被应用正常响应的问题, 包括 Maps / Messages / Weather 等 ... 

## 其他

- App 文本校对, @novialriptide @udanfacy22 
- 网站文本校对, 感谢 @kant @jfrsa

---

> Limited by macOS security strategy, you need to allow Mos to access to Accessibility Control to ensure that it is working properly.
If Mos already in the Accessibility Control list, just uncheck it and toggle it again. If it still doesn't work, try removing it from the list and adding it again.
You can check this for help: [Can't get access to accessibility correctly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly#cant-get-access-to-accessibility-correctly)

> If the macOS preventing the application running, you can check this for help: [If the App not work properly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly)

> [meow meow meow](https://meow.caldis.me)

## New features

- Greek language support, thanks to @Valamorde

- Ukrainian language support, thanks to @dittohead

- Updated application icon and status bar icon

## Fix

- In Catalyst apps, scrolling is not properly responded to immediately after scrolling stops, including Maps/Messages/Weather, etc...

## Other

- Wording improvement for App, @novialriptide @udanfacy22

- Wording improvement for Web, thanks to @kant @jfrsa

# [3.4.1](https://github.com/Caldis/Mos/releases/tag/3.4.1)

![IMG_1565](https://user-images.githubusercontent.com/3529490/194695642-39b0e9dd-0094-4f02-8b2c-68a5445577fa.jpg)

> 由于 macOS 的安全性限制, 你需要允许 Mos 访问系统的辅助功能的访问权限以确保其正常运行
若 Mos 已在辅助功能的授权列表中, 只需取消勾选后再度勾选即可; 如果仍然无效, 请尝试将其从列表中移除再添加
可以在此处查看帮助: [无法正确获取辅助功能权限](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

> 如果在初次启动应用时被系统阻止, 你可以查看帮助: [如果应用无法正常运行](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

> [如果想看大咪点这里](https://meow.caldis.me)

## 修正
 
- 隐藏状态栏图标功能无效的问题

---

> Limited by macOS security strategy, you need to allow Mos to access to Accessibility Control to ensure that it is working properly.
If Mos already in the Accessibility Control list, just uncheck it and toggle it again. If it still doesn't work, try removing it from the list and adding it again.
You can check this for help: [Can't get access to accessibility correctly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly#cant-get-access-to-accessibility-correctly)

> If the macOS preventing the application running, you can check this for help: [If the App not work properly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly)

> [meow meow meow](https://meow.caldis.me)

## Bug fix

- Fixed an issue will cause the hide status bar icon not working

# [3.4.0](https://github.com/Caldis/Mos/releases/tag/3.4.0)

![dji_fly_20220905_173318_321_1662372322759_pano](https://user-images.githubusercontent.com/3529490/193414140-26513387-606b-4a63-b88f-7402854038de.jpg)

> 由于 macOS 的安全性限制, 你需要允许 Mos 访问系统的辅助功能的访问权限以确保其正常运行
若 Mos 已在辅助功能的授权列表中, 只需取消勾选后再度勾选即可; 如果仍然无效, 请尝试将其从列表中移除再添加
可以在此处查看帮助: [无法正确获取辅助功能权限](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

> 如果在初次启动应用时被系统阻止, 你可以查看帮助: [如果应用无法正常运行](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

> [如果想看大咪点这里](https://meow.caldis.me)

## 优化

- 少许性能优化
- 繁體中文 (台灣) / 繁體中文 (香港) 的文本优化, 感谢 @pan93412 @ralphchung 的贡献
- 德语文本优化, 感谢 @mmairle 的贡献
- 英文文本优化, "white list" -> "allow list", 感谢 @tmchow 的贡献
- README 更新, 感谢 @kant @Goooler 的贡献

## 修正
 
- 降低了一些了由于内存泄露导致应用异常崩溃的概率 (实在是找不到哪里漏了)

---

> Limited by macOS security strategy, you need to allow Mos to access to Accessibility Control to ensure that it is working properly.
If Mos already in the Accessibility Control list, just uncheck it and toggle it again. If it still doesn't work, try removing it from the list and adding it again.
You can check this for help: [Can't get access to accessibility correctly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly#cant-get-access-to-accessibility-correctly)

> If the macOS preventing the application running, you can check this for help: [If the App not work properly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly)

> [meow meow meow](https://meow.caldis.me)

## Improvement

- Some performance optimizations
- Traditional Chinese (Taiwan) / Traditional Chinese (Hong Kong) language improvement, thanks to @pan93412 @ralphchung
- German language improvement, thanks to @mmairle
- English transition improvement, from term "white list" -> "allow list", thanks to @tmchow 
- README update, thanks to @kant @Goooler

## Bug fix

- Slightly reduced the probability of the application crash abnormally due to a memory leak

# [3.3.2](https://github.com/Caldis/Mos/releases/tag/3.3.2)

> 由于 macOS 的安全性限制, 你需要允许 Mos 访问系统的辅助功能的访问权限以确保其正常运行
若 Mos 已在辅助功能的授权列表中, 只需取消勾选后再度勾选即可; 如果仍然无效, 请尝试将其从列表中移除再添加
可以在此处查看帮助: [无法正确获取辅助功能权限](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

> 如果在初次启动应用时被系统阻止, 你可以查看帮助: [如果应用无法正常运行](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E5%BA%94%E7%94%A8%E6%97%A0%E6%B3%95%E6%AD%A3%E5%B8%B8%E8%BF%90%E8%A1%8C#%E6%97%A0%E6%B3%95%E6%AD%A3%E7%A1%AE%E8%8E%B7%E5%8F%96%E8%BE%85%E5%8A%A9%E5%8A%9F%E8%83%BD%E6%9D%83%E9%99%90)

## 修正

- 修复了禁用键无法生效的问题
- 修复恢复为预设值的状态不一致的问题
- 修复了例外列表的样式偏移问题

---

> Limited by macOS security strategy, you need to allow Mos to access to Accessibility Control to ensure that it is working properly.
If Mos already in the Accessibility Control list, just uncheck it and toggle it again. If it still doesn't work, try removing it from the list and adding it again.
You can check this for help: [Can't get access to accessibility correctly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly#cant-get-access-to-accessibility-correctly)

> If the macOS preventing the application running, you can check this for help: [If the App not work properly](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly)

## Bug Fix

- Fixed an issue that the disabled key cannot take effect
- Fixed inconsistent status of restoring to preset value
- Fixed the style offset problem of exception list

# [3.3.1](https://github.com/Caldis/Mos/releases/tag/3.3.1)

![2020-12-13 8a214628](https://user-images.githubusercontent.com/3529490/108588794-028cc280-7396-11eb-9f8a-bddb5795f5b1.jpg)
---

> 由于 macOS 的安全性限制, 你需要允许 Mos 访问系统的辅助功能的访问权限以确保其正常运行
若 Mos 已在辅助功能的授权列表中, 只需取消勾选后再度勾选即可

> 如果在初次启动应用时被系统阻止, 你可以查看帮助: [如果你无法执行应用](https://github.com/Caldis/Mos/wiki/%E5%A6%82%E6%9E%9C%E4%BD%A0%E6%97%A0%E6%B3%95%E6%89%A7%E8%A1%8C%E5%BA%94%E7%94%A8)

## 新特性

- 适配 BigSur 界面
- 适配 M1 芯片设备
由于我还没有相应设备, 我们仅仅重新编译了 Universual 的代码来适配, 目前尚存在一些兼容性问题, 您可以追踪 https://github.com/Caldis/Mos/issues/333 来获取最新动态, 如果您可以协助测试, 也十分欢迎在问题单内留言
- 例外应用的设置界面现在可以正确匹配其状态
- 例外应用可以正确地添加任何非 Bundle 类型的应用, 如 MineCraft 这类 Java 应用, 或某些来自 Steam 的游戏可执行文件
此外, 例外应用已经基于执行路径而不是 BundleID 匹配, 这意味着, 一旦你改变了应用的存放路径, 你需要重新配置其设置
这一变更可能会影响某些已添加的例外应用, 你或许需要重新添加并配置它们
- 例外应用现在可以修改显示的名称
- 滚动时点击鼠标左键可以停止滚动
- 俄文支持, 感谢 @mclvren 的翻译
- 韩文支持, 感谢 @readingsnail 的翻译
- 土耳其语支持, 感谢 @LeaveNhA Leav 的翻译
- 德语支持, 感谢 @lima0 Seli 的翻译

## 优化

- 滚动行为现在不会被携带到其他目标窗口
- 繁体中文文本优化, 感谢 @crizant 的翻译
- 英文文本优化, 感谢 @flash76 的翻译
- 文档支持, 感谢 @jackdcasey 的翻译

## 修正

- 修复了 BigSur 下状态栏图标无法完全隐藏的问题
- 修复了例外应用在某些情况下无法正确生效的问题
- 修复了在 Chrome 刷新时执行滚动导致页面被移出屏幕的问题
- 修复了 Logitech MX Master 系列鼠标的拇指轮无法被正确识别的问题

## 杂项

- 通过 BundleID 添加例外应用的方式被移除
- 现在使用 Swift Package 代替 CocoaPods

---

> Limited by macOS security strategy, you need to allow Mos to access to Accessibility Control to ensure that it is working properly.
If Mos already in the Accessibility Control list, just uncheck it and toggle it again.

> If the macOS preventing the application running, you can check this for help: [If the App isn’t allowed to open](https://github.com/Caldis/Mos/wiki/If-the-App-isn%E2%80%99t-allowed-to-open)

## New Features

- BigSur UI adaptation
- Adaptation to M1 chip
Since I don't have the latest device yet, we just recompile the Universual code for adaptation, so there are still some compatibility issues, you can track https://github.com/Caldis/Mos/issues/333 to get the latest news, if you can help to test, you are also very welcome in the questionnaire Leave a comment
- The exceptions settings screen now correctly matches its status
- Exceptions can correctly add any non-Bundle type application, such as Java applications like MineCraft, or certain game executables from Steam
In addition, the exceptions have been matched based on the execution path rather than the BundleID, which means that once you change the path where the app is stored, you will need to reconfigure its settings
This change may affect some of the exception apps that have been added, and you may need to re-add and reconfigure them
- Exceptional apps can change the displayed name now
- Scrolling can be stopped by clicking the left mouse button when scrolling
- Russian support, thanks to @mclvren for the translation
- Korean support, thanks to @readingsnail for the translation
- Turkish support, thanks to @LeaveNhA Leav for the translation
- German support, thanks to @lima0Seli for the translation

## Improvement

- Scrolling behavior is now not carried to other target windows
- Traditional Chinese text optimization, thanks to @crizant for translation
- English text optimization, thanks to @flash76 for translation
- Documentation support, thanks to @jackdcasey for the translation

## Bug Fix

- Fixed an issue  that the status bar icon could not be completely hidden under BigSur
- Fixed an issue where the exception application did not work correctly in some cases
- Fixed an issue that caused pages to be moved off the screen when performing scrolling on Chrome refresh
- Fixed an issue where the thumbwheel on Logitech MX Master series mouse was not recognized correctly

## Miscellaneous

- Adding exception apps via BundleID has been removed
- Now uses Swift Package instead of CocoaPods

# [3.1.0](https://github.com/Caldis/Mos/releases/tag/3.1.0)

![DJI_0236-HDR](https://user-images.githubusercontent.com/3529490/69168252-54122600-0b31-11ea-94c7-5074a35eba6d.jpg)
----

```
由于 macOS 的安全性限制, 你需要允许 Mos 访问系统的辅助功能的访问权限以确保其正常运行
如果 Mos 已在辅助功能的授权列表中却无法正常使用, 只需取消勾选后再度勾选即可
```

```
若系统提示 “程序已损坏” ，你需要在 “系统偏好设置 -> 安全性与隐私 -> 通用” 中允许程序运行
对于高版本的系统，你可能还需要借助命令行来编辑应用的 “com.apple.quarantine” 属性以允许程序的运行，请参考
https://superuser.com/questions/28384/what-should-i-do-about-com-apple-quarantine
```

## 新特性

- 现在你可以指定一个按钮为**加速键**, 按下后只需要轻轻滑动滚轮就可以在页面中来回冲刺
- 你现在可以为每个例外应用程序设定单独的滚动行为了。
- 在例外应用列表中, 你可以直接从正在运行的窗口程序中选择并添加爱。
- 在例外应用列表中, 现在可以手动输入应用程序的识别信息。如果你先前无法通过从文件选择的方式添加一个应用到例外列表中, 不妨用这个试试。不过使用这个路径添加的应用，列表将无法正确展示其图标。
- 在设置中增加了一个用于隐藏状态栏图标的选项。

## 优化

- 图标更新。
- 导览界面更新。
- 偏好设置界面更新。
- 考虑到**滚动监控**的使用频率, 现在它被雪藏了, 只有在按下 **Options** 并点击状态栏的图标后才能看到滚动监控的选项。

## 修正

- 重写了热键功能, (应该)修复了在某些情况下会卡住的问题。
- 在 macOS Catalina 下无法正常识别 Launchpad 的问题。
- 一些 UI 问题。
- 版本号过低的问题。

---

```
Limited by macOS security strategy, you need to allow Mos to access to Accessibility Control to ensure that it is working properly.
If Mos is not working properly when it's in the Accessibility Control list, just uncheck it and toggle it again.
```

```
If the system says "The program is damaged", you need to allow the program to run in "System Preferences -> Security and Privacy -> General"
For higher version systems, you may also need to edit the "com.apple.quarantine" property of the application with the help of the command line to allow the program to run, please refer to
https://superuser.com/questions/28384/what-should-i-do-about-com-apple-quarantine
```

## New Features

- Now you can specify a button for the **Acceleration button**. After enabled, you just need to scroll the wheel gracefully and you can swipe the page rapidly.
- You can now set its own independent scrolling behavior for each exception application.
- In the Exceptions application list, you can now select directly from the running window program.
- In the Exceptions application list, you can now manually enter the identification information for your application. If you can't add an app to the exception list by selecting it from a file, try this with a try. But for this reason, the list will not display its icon correctly.
- Added an option to hide the status bar icon.

## Improvement

- New icon.
- Improved introduction interface.
- Improved preferences interface.
- Since **Rolling Monitor** is used less frequently, it is now hidden. You can only see the options for scrolling monitoring when you press **Options** and click on the icon in the status bar.

## Bug Fix

- Rewritten the hotkey function, (should) fix the problem that will get stuck in some cases.
- Fix an issue with macOS Catalina that is not working properly due to its security policy
- There are some problems that are not there.

# [2.4.0-beta](https://github.com/Caldis/Mos/releases/tag/2.4.0-beta)

```
由于 macOS 10.14 的限制, Mos 只有在获取了辅助功能的访问权限后才可正常使用
更新版本后，你需要重新在设置的辅助功能中再次给 Mos 授权
如果已授权，请取消勾选并重新勾选一次
```

## 修正

亮色模式下的部分样式的问题

部分在例外应用程序列表中的应用程序无法被正确检测到的问题 
- 一般情况下, Mos 会检测指针所在位置的应用程序是否在例外应用列表中, 不管该窗口是否被激活或前置显示. 但部分应用程序无法通过该方式被识别, 如 Adobe Acrobat DC 等. 对于该类应用程序, 只有在其被激活或前置显示时, 才能被识别为例外应用程序.
- https://github.com/Caldis/Mos/issues/100, https://github.com/Caldis/Mos/issues/107

---

```
Limited by macOS 10.14, you need to allow Mos to access to Accessibility control.
After update Mos, you need to go to the System Preferences to allow Mos access Accessibility again.
If the entry has been checked, uncheck it and tick again.
```

## Fixed

Fixed some style problem in brightness mode

Fixed an issue will cause the applications in the exceptions application list are not correctly detected.
- In general, Mos will detect if the application at the location of the cursor is in the exception application list, regardless of whether the window is activated. However, some applications cannot be identified in this way, such as Adobe Acrobat DC, etc. This type of application can only be recognized as an exception application when it is activated.
- https://github.com/Caldis/Mos/issues/100, https://github.com/Caldis/Mos/issues/107

# [2.3.0](https://github.com/Caldis/Mos/releases/tag/2.3.0)

![img_8813](https://user-images.githubusercontent.com/3529490/42519702-3391c15a-8497-11e8-8358-9a551bc0c863.jpg)

```
由于 macOS 10.14 的限制, Mos 只有在获取到了辅助功能的访问权限后才可正常使用
更新版本后，你需要重新在设置的辅助功能中再次给 Mos 授权
如果已授权，请取消勾选并重新勾选一次
```

## 新功能

现已支持 MacOS 10.14 的 Dark Mode

现在, 首次启动 Mos 时将会有一个引导界面提供相关的使用指引, 并指导你开启辅助功能权限

## 优化

於偏好设置的关于页内增加了贡献者名单

翻转/禁用键现在将不会对新用户默认启用

## 修正

修正长时间使用的内存泄漏问题 https://github.com/Caldis/Mos/issues/85

---

```
Limited by macOS 10.14, you need to allow Mos to access to Accessibility control.
After update Mos, you need to go to the System Preferences to allow Mos access Accessibility again.
If the entry has been checked, uncheck it and tick again.
```

## New Feature

Support Dark Mode in macOS 10.14

Will show a Welcome Window when Mos first launch or just updated.

## Enhancement

Add contributors list in Preferences - About

The Toggle/Block Key is changed to disabled for new users

## Fixed

Fixed an issue will cause the memory leak when scrolling. https://github.com/Caldis/Mos/issues/85

# [2.2.6](https://github.com/Caldis/Mos/releases/tag/2.2.6)

```
更新版本后，你需要重新在设置的辅助功能中再次给 Mos 授权
如果已授权，请取消勾选并重新勾选一次, 否则例外应用检测功能将会失效
```

## 优化

优化了窗口检测机制，降低 CPU 占用，同时减少了平滑滚动失效的概率

优化了英文的界面文本，非常感谢 🎉 @godly-devotion 👏

你现在可以直接在偏好设置面板中直接输入数值来调整参数
- https://github.com/Caldis/Mos/issues/76

打开偏好设置面板或监控面板时将于 Dock 显示应用图标
- https://github.com/Caldis/Mos/issues/76

---

```
After update Mos, you need to go to the System Preferences to allow Mos access Accessibility again.
If the entry has been checked, uncheck it and tick again, otherwise the Exceptional setting will not apply.
```

## Enhancement

Improved the application detection mechanism, reduced CPU usage.

Improved English translation, thanks for contribution of 🎉 @godly-devotion 👏.

You can now directly enter values in the Preferences to adjust parameters.
- https://github.com/Caldis/Mos/issues/76

Shows the app icon on the Dock when opening the Preferences and Scroll Monitor
- https://github.com/Caldis/Mos/issues/76

# [2.2.2](https://github.com/Caldis/Mos/releases/tag/2.2.2)

![28113313528_b66f14fcb3_h](https://user-images.githubusercontent.com/3529490/39876445-c451acea-54a5-11e8-987e-f4523ba66a62.jpg)
- via [Playstation Blog](https://blog.us.playstation.com/2018/05/09/photo-mode-comes-to-god-of-war-today)

---

### 更新版本后, 你需要重新在设置的辅助功能中给 Mos 授权, 否则例外应用将会失效

## 修正

修复了在某些情况下可能导致平滑滚动失效的问题
- https://github.com/Caldis/Mos/issues/63
- https://github.com/Caldis/Mos/issues/69

修复了水平滚动无效的问题
- https://github.com/Caldis/Mos/issues/67

---

### After you update Mos, you need to go to the System Preferences to allow Mos access Accessibility again., otherwise the Exceptional Application's setting will not apply

## Fixed

Fixed an issue will cause smooth scrolling core crash in some situation.
- https://github.com/Caldis/Mos/issues/63
- https://github.com/Caldis/Mos/issues/69

Fixed an issue will cause horizon scrolling unprocessed. 
- https://github.com/Caldis/Mos/issues/67

# [2.2.0](https://github.com/Caldis/Mos/releases/tag/2.2.0)

真帅

![p2515058700](https://user-images.githubusercontent.com/3529490/38407226-37cf67cc-39ab-11e8-9c9a-20368beec006.jpg)


## 新功能

你现在可以为 "变换方向", "禁用平滑" 分别设定一个热键, 当按下热键时, 相应的操作将会被触发
你可以在高级设置界面找到这个选项
- https://github.com/Caldis/Mos/issues/33
- https://github.com/Caldis/Mos/issues/15

滚动监控界面现在可以同时呈现水平与垂直方向的数据

滚动监控界面增加了图表的重置按钮, 点击即可清空图表数据

## 优化

更新了 Chart 库的版本

优化了开始滚动时的加速效果

优化了繁体中文的部分翻译文本

优化了滚动监控界面的样式与执行效率

优化了例外应用的侦测逻辑
- 我们重写了侦测例外程序的逻辑, 目前基于指针坐标侦测对应坐标的窗口信息. 因此现在, 无需目标窗口处于激活状态也可正常侦测到对应的例外程序了. 
但是相应地, 由于侦测过程中使用到了更高级的系统 API [(AXUIElement)](https://developer.apple.com/documentation/applicationservices/axuielement.h). 因此, 你需要先授权 Mos 访问辅助功能的权限, 例外程序才能被启用. 当你进入设置界面的 "例外" 选项卡时, 你会看到相应的提示与引导帮助.

## 修正

修复了启动台中平滑滚动影响翻页的问题

修复了取消勾选界面上的 "开机启动" 时无法正确从用户登录项中移除的问题
- 使用了 https://github.com/Clipy/LoginServiceKit

---

## New Feature

You can now set a hotkey for "change direction" and "disable smoothing" respectively. When the hotkey is pressed, the corresponding operation will be triggered.
You can find this option in the advanced settings interface
- https://github.com/Caldis/Mos/issues/33
- https://github.com/Caldis/Mos/issues/15

The scrolling monitoring interface can now present horizontal and vertical data simultaneously

The scroll monitoring interface adds a reset button to the chart. Click to clear the chart data

## Enhance

Updated the version of the Chart library

Optimized the acceleration effect when starting scrolling

Partially translated text in Traditional Chinese is optimized

Optimize the style and execution efficiency of the scroll monitor interface

Optimized exception detection logic
- We have rewritten the logic to detect exceptions, currently based on the pointer coordinates to detect the corresponding window information. So now, the corresponding exception program can be normally detected without the target window active.
However, due to the use of the more advanced system API [(AXUIElement)](https://developer.apple.com/documentation/applicationservices/axuielement.h) in the detection process, you need to authorize Mos to access the Accessibility first. The permission of the function, the exception procedure can be enabled. When you enter the "Exceptions" tab of the settings screen, you will see the corresponding prompt and guide help.

## Fixed

Fixed issue with starting smooth scrolling in Taiwan

Fixed an issue that could not be properly removed from user login items when unchecking "Startup" on the interface
- Power by https://github.com/Clipy/LoginServiceKit


# [2.0.0](https://github.com/Caldis/Mos/releases/tag/2.0.0)

各位猎人们, 2.0 版本来啦 !
重构了所有代码, 大量的优化, 运行起来更高效.
我们还重写了主页, 欢迎造访: http://mos.caldis.me

不过, 如果不是它的话, 这次 Release 或许会来的更早一点,  一点点啦
> Monster Hunter : World

![monster hunter_ world_20180210161050](https://user-images.githubusercontent.com/3529490/37877380-eb44f678-308c-11e8-9148-af937ae9bdf6.jpg)

![monster hunter_ world_20180214222658](https://user-images.githubusercontent.com/3529490/37877381-ec69baa2-308c-11e8-860c-22ad9a764c29.png)


## 优化

重写了平滑滚动的插值算法, 一般情况下 CPU 占用下降较原先约 40-50%, 不过, 手感也会有所不同
- https://github.com/Caldis/Mos/issues/44

优化了内存占用, 较原先下降约 70-80%

状态栏菜单增加了图标示意, 语义更加明确了

## 新功能

现在你可以隐藏状态栏的图标了, 只需要按住 option 键, 再单击状态栏图标, 根据提示操作即可. 如果您需要重新显示状态栏的图标, 请使用活动监视器关闭 Mos, 再重新运行, 并点击通知中出现的 "显示图标" 按钮
- https://github.com/Caldis/Mos/issues/3

新增繁體中文支持, 如果您為港台地區用戶, 若發現任何語義問題, 我們非常歡迎您的反饋

## 修正

部分情况下的内存泄露

---

## Enhance

Rewrite the smooth scrolling interpolation algorithm. Under normal circumstances, the CPU usage is about 40-50% lower than the original. However, the feel will be little different.

Optimized memory footprint, about 70-80% lower than the original.

The status bar menu adds icons to clarify the semantics.

## New Feature

Now you can hide the icon of the status bar, just hold down the option key, click on the status bar icon, and follow the prompts. If you need to re-display the icon in the status bar, use the activity monitor to turn off Mos, and then Run, and click the "Show Icon" button that appears in the notification.

## Fixed 

Memory leak in some cases.


# [1.7.0](https://github.com/Caldis/Mos/releases/tag/1.7.0)

## 新功能

现在支持鼠标横向滚动的平滑效果

## 修正

MacOS 10.13 下的偏好设置窗口错位问题
- https://github.com/Caldis/Mos/issues/35

切换系统用户时滚动失效的问题
- https://github.com/Caldis/Mos/issues/31

## 优化

更新了 Charts 的版本

---

## New Feature

Support handling the horizon scrolling smooth.

## Fixed 

Fixed preferences window size problem in MacOS 10.13.

Fixed problem that cause system can't handling scrolling correctly when user session switched.

## Enhance

Upgrade Charts.


# [1.6.1](https://github.com/Caldis/Mos/releases/tag/1.6.1)

想起了当年玩PSP的日子

> DJMAX: Respect

![dfafa3b1-27b2-4762-ac9a-413b4412a2e8](https://user-images.githubusercontent.com/3529490/29993023-d4bbb8e8-8fdc-11e7-8290-4c295a94cb12.jpg)


## 修正

在某些应用窗口中 Mos 会异常崩溃的问题 
- 由于某些应用窗口是以子进程方式执行(如 Android Studio 的模拟器窗口, 感谢 @CasparGX 的反馈) 而子进程本身并不拥有 BundleID, 其 BundleID 是依赖其父进程的 , 导致无法在忽略列表中找到对应的排除项而导致应用异常退出

## Fixed 

Fixed a problem that could cause Mos to crash. 
- When the target application was running in a child process state.

# [1.6.0](https://github.com/Caldis/Mos/releases/tag/1.6.0)

隔了几个月看回之前写的代码, 真的是一泡污... ...  得找个时间重写一次

> 塞尔达传说：荒野之息
> The Legend of Zelda：Breath of the Wild

![link_lrg](https://user-images.githubusercontent.com/3529490/29495421-6c77895a-85f1-11e7-91f0-eca123ceadf9.png)

> https://dribbble.com/shots/3488659-Hero-of-the-Wild

## 新功能

忽略的面板改成了 "例外", 且新增了白名单模式
- 白名单模式在启用之后 Mos 就仅针对列表内的应用有效, 然后你可以基于此再来调整是不是要禁用 Mos 的平滑或者翻转滚动效果

高级设置内加了个峰值位置调整, 你可以用它来调整加速曲线什么时候该加速什么时候该减速
- 如果你想滚动启动时反应更灵敏, 停止时更为缓慢, 就往小了调
- 如果你想滚动在启动开始时更为平缓, 停止时更迅速, 就往大了整

## 修正

开机启动勾选框的状态无法保存的问题

## 优化

现在在Launchpad中会始终禁用平滑滚动

稍微改进了下写的很烂的判断逻辑

提高了可以最大滚动的峰值

---

## New Feature

Add allow list mode in Ignore panel.

Add Peak setting in Advance panel.

## Fixed 

Fix the issue of checkbox's state can't be save currently which in General panel of Launch on login.

## Enhance

The smooth scrolling will always disabled on launchpad.

Increase the maximum value of the Speed Setting and Time Setting on advance panel.


# [1.5.0](https://github.com/Caldis/Mos/releases/tag/1.5.0)

久违的双休...

![qq20170324-230657](https://cloud.githubusercontent.com/assets/3529490/24300202/a1f30b48-10e6-11e7-9bea-c4cd1b1d9514.png)

## 新功能

您现在可以在设置面板中直接将Mos设为开机启动

## 修正

修正了滚动监控界面的布局样式问题

修正了Launchpad添加到忽略列表后无效的问题

修正了忽略列表中的应用程序在特定情况下忽略翻转滚动失效的问题

---

## New Feature

Now you can directly add Mos to login item from preferences panel. 

## Fixed

Fix a layout issue on Scroll Monitor

Fix a issue that will cause Launchpad.app could not be handled properly in ignore list.

Fix a issue that scroll reverse option in ignore list could not be handled properly.


# [1.4.4](https://github.com/Caldis/Mos/releases/tag/1.4.4)

## 修正

修正了在 MacOS El Capitan (10.11) 下无法正常使用的问题 (仅在10.11.6下测试)

---

## Fixed

Fixed a problem will cause the Mos could not be handled properly while using MacOS El Capitan (Test on 10.11.6).


# [1.4.2](https://github.com/Caldis/Mos/releases/tag/1.4.2)

## 修正

(或许) 修正了部分鼠标在缓慢滚动时无法正确处理的问题

---

## Fixed

(Maybe) Fixed a problem where some of the mouse wheel could not be handled properly while scrolling slowly.


# [1.4.1](https://github.com/Caldis/Mos/releases/tag/1.4.1)

> GitHub 上存在该 prerelease, 但未提供 release notes。

---

> This prerelease exists on GitHub, but no release notes were provided.


# [1.4.0](https://github.com/Caldis/Mos/releases/tag/1.4.0)

现已采用DMG打包方式

## 新功能

鼠标滚动事件的Log功能, 用户可以通过在滚动监视器内的记录功能来记录自己的问题滚动数据, 便于反馈修正问题

## 修正

部分英文翻译语法错误

---

Now using DMG file to package the application.

## New Feature

Scroll Event Recorder, user now can record the scroll event and feedback to us.

## Fixed

Some translation mistake.


# [1.3.1](https://github.com/Caldis/Mos/releases/tag/1.3.1)

## 修正

部分英文翻译语法错误, 感谢 @OrcaXS 对英文国际化的支持
忽略应用列表中的应用名称乱码问题

---

## Fixed

Some translation mistake, special thanks to @OrcaXS support for English localization.
Ignore list characters garbled.


# [1.3.0](https://github.com/Caldis/Mos/releases/tag/1.3.0)

## 新功能

应用程序忽略列表功能, 可以在设置-忽略中将特定的程序禁用平滑滚动/反转滚动

## 修正

平滑滚动的部分判断逻辑

---

## New Feature

Added new feature "Application Ignored List", you can disable the smooth/reverse scroll in specific application.

## Fixed

SmoothScroll performance improved.


# [1.0.0](https://github.com/Caldis/Mos/releases/tag/1.0.0)

第一版发布 !

---

First version released !


# [1.0](https://github.com/Caldis/Mos/releases/tag/1.0)

> GitHub 上存在该 prerelease, 但未提供 release notes。

---

> This prerelease exists on GitHub, but no release notes were provided.
