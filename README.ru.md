<p align="center">
  <a href="http://mos.caldis.me/">
    <img width="320" src="https://github.com/Caldis/Mos/blob/master/dmg/dmg-icon.png?raw=true">
  </a>
</p>


# Mos

![Xcode 9.0+](https://img.shields.io/badge/Xcode-9.0%2B-blue.svg)
![Swift 4.0+](https://img.shields.io/badge/Swift-4.0%2B-orange.svg)

Бесплатное и простое приложение, позволяющее колесу мыши плавно прокручиваться в macOS.

[中文](https://github.com/Caldis/Mos/blob/master/README.md) | [English](https://github.com/Caldis/Mos/blob/master/README.enUS.md) |
[Русский](https://github.com/Caldis/Mos/blob/master/README.ru.md)


## Главная страница

http://mos.caldis.me/


## Функции

- Сделайте прокрутку колеса мыши плавной и настройте ускорение и кривые отклика.
- Настраивайте сенсорную панель и мышь отдельно, включая независимое сглаживание и инверсию по вертикали и горизонтали.
- Режим «Эмуляция трекпада» дарит обычной мыши непрерывную прокрутку, как на тачпаде.
- Панель «Кнопки» записывает события мыши или клавиатуры и связывает их с системными сочетаниями в один клик.
- Модуль «Приложения» позволяет каждому приложению наследовать или переопределять правила прокрутки, хоткеев и привязок кнопок.
- Окна мониторинга прокрутки и кнопок показывают живые логи, помогая с диагностикой.

## Что нового в 4.0

- Настройки получили новый дизайн: PrimaryButton, таблицы и всплывающие панели выглядят единообразно в светлой и тёмной теме.
- Привязки кнопок автоматически сохраняются, подсвечивают дубликаты и позволяют быстро редактировать найденные записи.
- Каталог системных сочетаний пополнился скриншотами, записью экрана, переключением рабочих столов и другими опциями — стандартные привязки стали умнее.
- Локализации переехали в каталоги строк Xcode, добавлены новые тексты для кнопок и сочетаний, а сайт теперь доступен на нескольких языках.
- Mission Control, переключение приложений и другие крайние сценарии больше не ломают плавную прокрутку — поведение стало стабильнее.


## Загрузка & Установка

### Homebrew

Если вы хотите установить приложение с помощью [Homebrew](https://brew.sh):

```bash
$ brew install --cask mos
```

Приложение будет находится по адресу `/Applications/Mos.app`.

Чтобы обновить приложение:

```bash
$ brew update
$ brew reinstall mos
```

Закройте и перезапустите приложение.

### Ручная установка

- [GithubRelease](https://github.com/Caldis/Mos/releases/)


## Инструкция

- [Wiki](https://github.com/Caldis/Mos/wiki)


## Благодарность

- [Charts](https://github.com/danielgindi/Charts)
- [iconfont.cn](http://www.iconfont.cn)
- [LoginServiceKit](https://github.com/Clipy/LoginServiceKit)
- [Smoothscroll-for-websites](https://github.com/galambalazs/smoothscroll-for-websites)


## Содействие

Не стесняйтесь представлять или предлагать улучшения кода или перевода Mos на разные языки. Пожалуйста, отправляйте вопросы через [GitHub issues](https://github.com/Caldis/Mos/issues). Если вы хорошо разбираетесь в программировании, отправьте PR напрямую!


## ЛИЦЕНЗИЯ

Copyright (c) 2018 Caldis rights reserved.

[CC Attribution-NonCommercial](http://creativecommons.org/licenses/by-nc/4.0/)

Не загружайте Mos в App Store.
