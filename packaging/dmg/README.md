# DMG 构建说明

创建 Mos 安装用的 DMG, 使用 create-dmg 脚本实现。

先安装 https://github.com/create-dmg/create-dmg

如果 command 报错记得 chmod +x 一下。

目录内容:

- `assets/dmg-bg.png`: DMG 背景图, 分辨率 700x400

- `assets/dmg-icon.png`: DMG 图标, 分辨率 1204x1024

- `archive/`: 历史设计素材

使用方式:

```bash
packaging/dmg/create-dmg.command /path/to/Mos.app
```

也可以把 `Mos.app` 放在 `packaging/dmg/` 下, 然后直接运行:

```bash
packaging/dmg/create-dmg.command
```
