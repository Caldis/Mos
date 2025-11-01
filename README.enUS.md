<p align="center">
  <a href="http://mos.caldis.me/">
    <img width="320" src="https://github.com/Caldis/Mos/blob/master/dmg/dmg-icon.png?raw=true">
  </a>
</p>


# Mos

![Xcode 9.0+](https://img.shields.io/badge/Xcode-9.0%2B-blue.svg)
![Swift 4.0+](https://img.shields.io/badge/Swift-4.0%2B-orange.svg)

A free & simple app to allow your mouse wheel to scroll smoothly on macOS.

[中文](https://github.com/Caldis/Mos/blob/master/README.md) | [English](https://github.com/Caldis/Mos/blob/master/README.enUS.md) |
[Русский](https://github.com/Caldis/Mos/blob/master/README.ru.md)


## Homepage

http://mos.caldis.me/


## Features

- Smooth out your mouse wheel and customize acceleration and easing curves.
- Configure touchpad and mouse wheel independently, including per-axis smooth & reverse settings.
- Simulate trackpad scrolling on a regular mouse for a continuous, touch-like experience.
- New “Buttons” panel records mouse or keyboard events and binds them to system shortcuts with one click.
- The “Application” module lets each app inherit or override scroll, shortcut, and button-binding rules.
- Scroll and button monitors visualize live events to help with troubleshooting.

## What’s new in 4.0

- Preferences got a fresh redesign: PrimaryButton, table views, and popovers now feel consistent in both light and dark mode.
- Button bindings persist automatically, surface duplicate recordings, and highlight existing entries for quick editing.
- The shortcut catalog now includes screenshots, screen recording, space switching, and more—default mappings are smarter out of the box.
- Localization moved to Xcode string catalogs; new strings for buttons and shortcuts land alongside a multilingual website refresh.
- Mission Control, app switching, and other edge cases no longer break smooth scrolling, making daily use more reliable.


## Download & Install

### Homebrew

If you wish to install the application from [Homebrew](https://brew.sh):

```bash
$ brew install --cask mos
```

The application will live at `/Applications/Mos.app`.

To update the app:

```bash
$ brew update
$ brew reinstall mos
```

Quit then relaunch the app.

### Manual Installation

- [GithubRelease](https://github.com/Caldis/Mos/releases/)


## Guide

- [Wiki](https://github.com/Caldis/Mos/wiki)


## Thanks

- [Charts](https://github.com/danielgindi/Charts)
- [iconfont.cn](http://www.iconfont.cn)
- [LoginServiceKit](https://github.com/Clipy/LoginServiceKit)
- [Smoothscroll-for-websites](https://github.com/galambalazs/smoothscroll-for-websites)


## Contributing

Feel free to submit or propose improvements to the code or to the translation of Mos in different languages. Please submit new issues through [GitHub issues](https://github.com/Caldis/Mos/issues). If you are good at coding, please submit a PR directly!


## LICENSE

Copyright (c) 2018 Caldis rights reserved.

[CC Attribution-NonCommercial](http://creativecommons.org/licenses/by-nc/4.0/)

Do not upload Mos to the App Store.
