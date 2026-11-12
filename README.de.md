<p align="center">
  <a href="https://mos.caldis.me/">
    <img width="160" src="assets/readme/app-icon.png" alt="Mos app icon">
  </a>
</p>

<h1 align="center">Mos</h1>

<p align="center">
  Macht das Scrollen mit dem Mausrad unter macOS so flüssig wie mit einem Trackpad, ohne die Präzision einer Maus zu verlieren.
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
  <a href="https://mos.caldis.me/">Homepage</a> ·
  <a href="https://github.com/Caldis/Mos/releases">Download</a> ·
  <a href="https://github.com/Caldis/Mos/wiki">Wiki</a> ·
  <a href="https://github.com/Caldis/Mos/discussions">Discussions</a>
</p>

<p align="center">
  <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app scroll settings" width="920">
</p>

## Warum Mos

Das Scrollen mit einem normalen Mausrad fühlt sich unter macOS oft sprunghaft an. Dem Mausrad fehlt häufig die Präzision, um die gleichmäßige und vorhersehbare Trägheit eines Trackpads zu erreichen. Mos übernimmt Mausrad-Ereignisse und wandelt rohe Delta-Werte per Interpolation in flüssigeres Scrollen um, während du weiterhin kontrollierst, wie sich jede App, jede Achse und jede Taste verhält.

Außerdem kannst du mit Mos beliebige Maustasten neu belegen oder ihr Verhalten umschreiben, damit sie zu deinem Workflow passen.

Mos ist ein kostenloses Open-Source-Menüleistenwerkzeug für macOS 10.13 und neuer.

## Funktionshighlights

- **Flüssiges Scrollen**: Passe Mindestschritt, Geschwindigkeitsverstärkung und Dauer an oder aktiviere den Trackpad-Simulationsmodus.
- **Unabhängige Achsen**: Konfiguriere Glättung und umgekehrte Richtung getrennt für vertikales und horizontales Scrollen.
- **Scroll-Hotkeys**: Belege eigene Tasten für Beschleunigung, Achsenumwandlung und das vorübergehende Deaktivieren des flüssigen Scrollens.
- **App-spezifische Profile**: Jede App kann globale Einstellungen übernehmen oder Scroll-, Tastaturkürzel- und Tastenbindungsregeln einzeln überschreiben.
- **Tastenbindungen**: Zeichne Maus-, Tastatur- oder eigene Ereignisse auf und binde sie an Systemaktionen, Tastaturkürzel, Apps, Skripte oder Dateien.
- **Aktionsbibliothek**: Integrierte Aktionen für Mission Control, Spaces, Bildschirmfotos, Finder-Operationen, Dokumentbearbeitung, Mausscrollen und mehr.
- **Logi/HID++-Unterstützung**: Verarbeitet Logitech-Tastenereignisse von Bolt, Unifying-Empfängern und direkt per Bluetooth verbundenen Geräten, einschließlich Logi-spezifischer Aktionen.

## Screenshots

| Scroll-Anpassung | App-spezifische Profile |
| --- | --- |
| <img src="assets/readme/en-us/scrolling.png" alt="Mos scroll settings" width="420"> | <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app profile settings" width="420"> |

| Apps, Skripte oder Dateien öffnen | Aktionsbibliothek |
| --- | --- |
| <img src="assets/readme/en-us/buttons-open.png" alt="Mos open action" width="420"> | <img src="assets/readme/en-us/buttons-action.png" alt="Mos action library" width="420"> |

## Download & Installation

### Manuelle Installation

Lade die neueste Version von [GitHub Releases](https://github.com/Caldis/Mos/releases) herunter, entpacke sie und verschiebe `Mos.app` nach `/Applications`.

Beim ersten Start kann macOS dich bitten, Mos die Berechtigung für Bedienungshilfen zu erteilen. Mos benötigt diese Berechtigung, um Scroll-Ereignisse zu lesen und neu zu schreiben. Wenn die App nach der Freigabe trotzdem nicht funktioniert, siehe den [Leitfaden zur Fehlerbehebung bei Berechtigungen](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly).

### Homebrew

Wenn du Apps lieber mit Homebrew verwaltest:

```bash
brew install --cask mos
```

Aktualisieren:

```bash
brew update
brew upgrade --cask mos
```

## Mitwirken

Mos ist ein kleines Dienstprogramm, das Systemeingaben, Bedienungshilfen-Berechtigungen, Logi/HID-Geräte und dauerhaft gespeicherte Benutzereinstellungen berührt. Wartungsaufwand und Regressionsrisiko sind real, deshalb bevorzugen wir kleine, fokussierte Änderungen.

Änderungen an Logi/HID, Bedienungshilfen, Signierung, Notarisierung, App-Updates oder Tests mit echten Geräten sind riskanter. Bitte erkläre den Hintergrund in einem Issue oder in Discussions, bevor du in diesen Bereichen einen größeren PR öffnest.

Beschreibe im PR bitte Motivation, Validierung und mögliche Auswirkungen auf das Verhalten.

> KI-geschriebener Code ist inzwischen normal, und wir verstehen, dass viele PRs mit KI-Unterstützung entstehen, unsere eigene Arbeit eingeschlossen. Trotzdem muss die einreichende Person verstehen, kuratieren und überprüfen, was jede geänderte Zeile tatsächlich tut, denn jedes PR-Review kostet Zeit.

### Sehr willkommen

- Kleine Bugfixes mit Reproduktionsschritten oder Validierungsnotizen.
- UI/UX-Verbesserungen wie Layout, Texte, Lesbarkeit und kleine Onboarding-Details.
- Kleine Sicherheitsverbesserungen, etwa sicherere Behandlung von Berechtigungszuständen, Eingabeschutz und Grenzprüfungen.
- Verbesserungen an Lokalisierung, Dokumentation und Tests.
- PRs mit einem klaren Thema, begrenzten Änderungen und überschaubarer Review-Fläche.

### Was wir vorerst nicht mergen

- Große neue Funktionen, Module oder Architektur-Umbauten ohne vorherige Diskussion.
- Umfangreiche KI-generierte Rewrites, Formatierungswellen, Migrationen oder beiläufige Aufräumarbeiten.
- Verhaltensänderungen, die Eingabeereignisse, Berechtigungsdialoge, App-Updates, alte Benutzerdaten oder persistente Konfigurationsformate betreffen.
- Große maschinell erzeugte Übersetzungssets, besonders wenn sie nicht von Muttersprachlern geprüft werden können.

Alle Formen von Beiträgen sind willkommen. Wenn du Vorschläge oder Feedback hast, öffne gerne ein [Issue](https://github.com/Caldis/Mos/issues).

Wenn du dich für eine neue Funktion begeisterst, starte bitte zuerst in [Discussions](https://github.com/Caldis/Mos/discussions).

## Dank

- [Charts](https://github.com/danielgindi/Charts)
- [LoginServiceKit](https://github.com/Clipy/LoginServiceKit)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Smoothscroll-for-websites](https://github.com/galambalazs/smoothscroll-for-websites)
- [Solaar](https://github.com/pwr-Solaar/Solaar)

## License

Copyright (c) 2017-2026 Caldis. All rights reserved.

Mos ist unter [CC BY-NC 4.0](http://creativecommons.org/licenses/by-nc/4.0/) lizenziert. Lade Mos bitte nicht in den App Store hoch.
