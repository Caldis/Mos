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

Add white list mode in Ignore panel.

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


# [1.4.4](https://github.com/Caldis/Mos/releases/tag/1.4.2)

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