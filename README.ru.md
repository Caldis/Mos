<p align="center">
  <a href="https://mos.caldis.me/">
    <img width="160" src="assets/readme/app-icon.png" alt="Mos app icon">
  </a>
</p>

<h1 align="center">Mos</h1>

<p align="center">
  Сделайте прокрутку колесом мыши на macOS такой же плавной, как на трекпаде, сохранив точность мыши.
</p>

<p align="center">
  <a href="https://github.com/Caldis/Mos/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/Caldis/Mos?style=flat-square"></a>
  <img alt="macOS 10.13+" src="https://img.shields.io/badge/macOS-10.13%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="License: CC BY-NC 4.0" src="https://img.shields.io/badge/license-CC%20BY--NC%204.0-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="README.enUS.md">English</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.id.md">Bahasa Indonesia</a>
</p>

<p align="center">
  <a href="https://mos.caldis.me/">Сайт</a> ·
  <a href="https://github.com/Caldis/Mos/releases">Скачать</a> ·
  <a href="https://github.com/Caldis/Mos/wiki">Wiki</a> ·
  <a href="https://github.com/Caldis/Mos/discussions">Discussions</a>
</p>

<p align="center">
  <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app scroll settings" width="920">
</p>

## Зачем нужен Mos

Прокрутка колесом мыши на macOS часто ощущается резкой: ей не хватает непрерывной и предсказуемой инерции трекпада. Mos перехватывает события колеса мыши и превращает исходные дельты в более плавную прокрутку, оставляя вам контроль над приложениями, осями и кнопками.

Mos также позволяет переназначать или переопределять любую кнопку мыши под ваш рабочий процесс.

Mos — бесплатная open-source утилита для строки меню, поддерживающая macOS 10.13 и новее.

## Возможности

- **Плавная прокрутка**: настраивайте минимальный шаг, усиление скорости и длительность, либо включайте режим имитации трекпада.
- **Независимые оси**: задавайте сглаживание и обратное направление отдельно для вертикальной и горизонтальной прокрутки.
- **Горячие клавиши прокрутки**: привязывайте любые клавиши для ускорения, смены направления и временного отключения плавной прокрутки.
- **Профили для приложений**: каждое приложение может наследовать глобальные настройки или переопределять прокрутку, сочетания клавиш и привязки кнопок.
- **Привязки кнопок**: записывайте события мыши, клавиатуры или пользовательские события и назначайте им системные действия, сочетания, запуск приложений, скриптов или файлов.
- **Библиотека действий**: встроенные действия для Mission Control, Spaces, скриншотов, Finder, редактирования документов, прокрутки мышью и не только.
- **Поддержка Logi/HID++**: поддерживаются события кнопок Logitech через Bolt, Unifying и прямое Bluetooth-подключение, включая действия Logi.

## Скриншоты

| Настройка прокрутки | Профили приложений |
| --- | --- |
| <img src="assets/readme/en-us/scrolling.png" alt="Mos scroll settings" width="420"> | <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app profile settings" width="420"> |

| Открытие приложений, скриптов или файлов | Библиотека действий |
| --- | --- |
| <img src="assets/readme/en-us/buttons-open.png" alt="Mos open action" width="420"> | <img src="assets/readme/en-us/buttons-action.png" alt="Mos action library" width="420"> |

## Загрузка и установка

### Ручная установка

Скачайте последнюю версию из [GitHub Releases](https://github.com/Caldis/Mos/releases), распакуйте архив и переместите `Mos.app` в `/Applications`.

При первом запуске macOS может попросить выдать Mos разрешение Accessibility. Mos использует это разрешение, чтобы читать и переписывать события прокрутки. Если после выдачи разрешения приложение все еще не работает, см. [инструкцию по устранению проблем с разрешениями](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly).

### Homebrew

Если вы предпочитаете устанавливать приложения через Homebrew:

```bash
brew install --cask mos
```

Обновление:

```bash
brew update
brew upgrade --cask mos
```

## Участие

Mos перехватывает системный ввод, использует Accessibility, работает с Logi/HID-устройствами и сохраняемыми пользовательскими настройками. Стоимость поддержки и риск регрессий реальны, поэтому мы предпочитаем небольшие и сфокусированные изменения.

Изменения, затрагивающие Logi/HID, Accessibility, подпись, notarization, обновления приложения или тестирование на реальных устройствах, несут повышенный риск. Пожалуйста, сначала опишите контекст в issue или Discussions.

В описании PR укажите мотивацию, способ проверки и возможное влияние на поведение.

> Код, написанный с помощью AI, стал обычным явлением, и мы понимаем, что многие PR теперь создаются с AI-помощью, включая нашу собственную работу. Но автор PR должен сам понимать, отбирать и проверять, что делает каждая строка, потому что review каждого PR имеет стоимость.

### Очень приветствуется

- Небольшие исправления bug с шагами воспроизведения или описанием проверки.
- Точечные UI/UX-улучшения: layout, тексты, читаемость и onboarding.
- Небольшие security-улучшения: более безопасная обработка разрешений, защита ввода и проверки границ.
- Локализация, документация и тесты.
- PR на одну тему с небольшим числом изменений и понятной областью review.

### Пока не принимаем

- Крупные новые функции, модули или архитектурные переписывания без предварительного обсуждения.
- Массовые AI-сгенерированные переписывания, форматирование, миграции или «попутные улучшения».
- Изменения поведения, влияющие на обработку input events, запросы разрешений, обновления приложения, чтение старых пользовательских данных или формат сохраняемых настроек.
- Большие наборы машинных переводов, особенно если их не может проверить носитель языка.

Мы рады любому участию. Если у вас есть предложения или обратная связь, откройте [issue](https://github.com/Caldis/Mos/issues).

Если вы особенно заинтересованы в какой-то функции, начните с [Discussions](https://github.com/Caldis/Mos/discussions).

## Благодарности

- [Charts](https://github.com/danielgindi/Charts)
- [LoginServiceKit](https://github.com/Clipy/LoginServiceKit)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Smoothscroll-for-websites](https://github.com/galambalazs/smoothscroll-for-websites)
- [Solaar](https://github.com/pwr-Solaar/Solaar)

## License

Copyright (c) 2017-2026 Caldis. All rights reserved.

Mos распространяется по лицензии [CC BY-NC 4.0](http://creativecommons.org/licenses/by-nc/4.0/). Не загружайте Mos в App Store.
