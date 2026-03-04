# DictateFlow

Lokale Diktier-App für macOS 14+ mit `whisper.cpp`, optionaler KI-Nachbearbeitung über `Ollama`, globalem Hotkey, Menüleisten-Steuerung und schwebendem Overlay.

## Überblick

DictateFlow ist auf Datenschutz und Geschwindigkeit ausgelegt:

- Transkription läuft lokal über `whisper.cpp`.
- KI-Umformulierung läuft lokal über `ollama run ...`.
- Text kann automatisch an der Cursorposition eingefügt werden (`CMD+V` via Accessibility API) oder nur in die Zwischenablage kopiert werden.
- Verlauf wird lokal in SQLite gespeichert.

Standardmäßig ist der Modus auf **Reines Diktat** gesetzt. KI ist also bei Erststart aus.
Standardmäßig ist außerdem das Profil **Erinnerungen niederschreiben** vorausgewählt.

## Kernfunktionen

- SwiftUI-Mac-App mit Tabs: Aufnahme, Verlauf, Einstellungen
- Aufgeräumtes, card-basiertes UI-Layout für Aufnahme, Verlauf und Einstellungen
- Aufnahme-Status: `Bereit`, `Aufnahme läuft`, `Verarbeitung…`, `KI-Bearbeitung…`, `Fehler`
- AVFoundation-Aufnahme als WAV/PCM (16kHz, mono)
- Lokale Whisper-Transkription mit Modellwahl
- Optionale KI-Nachbearbeitung mit parametrisierbarem Prompt
- Sprachbefehle im Transkript (z. B. `neuer Absatz`, `nummerierte Liste`, `Stichpunkte`)
- Globaler Hotkey (konfigurierbar), inkl. Push-to-Talk
- Menüleisten-Fenster mit Status, letzter Transkription und Mikrofon-Auswahl
- Menüleisten-Fenster in kompakter Breite (zuletzt um ~25 % verkleinert)
- Floating Overlay (optional, always-on-top, mit Modus `fest verankert` oder `verschiebbar`)
- Auto-Paste (optional) mit klarer Accessibility-Fehlerbehandlung
- Setup-Assistent für Erstinstallation (Homebrew, Tools, Rechte)

## Anforderungen

- macOS 14 oder neuer
- Xcode 15+ (zum Entwickeln/Bauen)
- `xcodegen` (zum Generieren des Xcode-Projekts aus `project.yml`)
- Für KI-Modus: lokale Ollama-Installation + verfügbares Ollama-Modell

## Schnellstart (Empfohlen)

1. App starten.
2. Setup-Assistent öffnen (falls nicht automatisch sichtbar).
3. Homebrew prüfen/installieren.
4. `whisper-cpp` und `ollama` installieren.
5. Whisper-Modell herunterladen (mind. `small`).
6. Mikrofon erlauben.
7. Bedienungshilfen erlauben (nur zwingend, wenn Auto-Einfügen aktiv ist).
8. Aufnahme starten.

## Manuelle Installation (Alternative)

### 1) Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2) Whisper + Ollama

```bash
brew install whisper-cpp
brew install ollama
```

### 3) Whisper-Modell (Beispiel: Small)

```bash
mkdir -p "$HOME/Library/Application Support/DictateFlow/whisper-models"
curl -L --fail \
  -o "$HOME/Library/Application Support/DictateFlow/whisper-models/ggml-small.bin" \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
```

### 4) Optional Ollama-Modell laden

```bash
ollama pull llama3.1
```

## Build & Run

### Projekt generieren

```bash
xcodegen generate
```

### In Xcode öffnen

```bash
open DictateFlow.xcodeproj
```

### CLI-Build

```bash
xcodebuild \
  -project DictateFlow.xcodeproj \
  -scheme DictateFlow \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Nutzung

### Aufnahme starten

- Im Tab **Aufnahme** über Start/Stopp
- Über globalen Hotkey
- Über Menüleisten-Fenster
- Über Floating Overlay (wenn aktiviert)

### UI-Layout

- **Aufnahme**: klare Karten für Status, Diktiersteuerung und letzte Transkriptionen
- **Verlauf**: zweigeteiltes, ruhiges Panel-Layout (Liste links, Detaileditor rechts)
- **Einstellungen**: strukturierter Header + gruppierte Konfigurationsblöcke

### Overlay-Verhalten

- Idle: kleiner Mikrofon-Button
- Aufnahme aktiv: `X` bricht die Aufnahme ab (ohne Transkription)
- Aufnahme aktiv: roter `Stop` beendet Aufnahme und startet Transkription
- Audio-Spektrum visualisiert Eingangspegel
- Overlay kann per Setting fixiert oder verschiebbar geschaltet werden
- Bei deaktiviertem Verschiebe-Modus bleibt das Overlay fest an der zuletzt gesetzten Position
- Nur `Position zurücksetzen` setzt das Overlay auf die Initialposition zurück
- Die Overlay-Position bleibt auch nach Start/Stopp einer Aufnahme erhalten (in beiden Modi)

### Diktiermodi

- **Reines Diktat**: 1:1 Transkript (plus einfache Sprachbefehle-Transformation)
- **KI-Umformulierung**: LLM-Pipeline über Ollama mit Prompt-Stil und Profil-Hinweis

### Profile

- Standardprofil: **Erinnerungen niederschreiben**
- E-Mail
- Ticket
- Meetingnotiz
- Erinnerungen niederschreiben

### Sprachoptionen

- Primäre Transkriptionssprache
- Zusätzliche Fallback-Sprachen
- `Auto` möglich

### Modelloptionen

App-seitig auswählbar:

- Parakeet v3
- Whisper Tiny
- Whisper Base
- Whisper Small
- Whisper Medium
- Whisper Large v3 Turbo
- Whisper Large v3

Hinweis: `Parakeet v3` ist aktuell ein Profil und nutzt zur Laufzeit Whisper Large v3 Turbo.

## Empfehlungslogik für Whisper-Modelle

- Deutsch und viele europäische Sprachen: `Small`
- Japanisch/Chinesisch: `Medium` oder größer
- Maximale Genauigkeit: `Large v3`

## Einstellungen im Überblick

- Whisper CLI-Pfad + Auto-Detect
- Whisper-Modellordner + Auto-Detect
- Ollama CLI-Pfad + Auto-Detect
- Ollama-Modellname
- Diktiermodus (Default: Reines Diktat)
- Prompt-Stil + benutzerdefinierte Prompt-Template-Platzhalter
- Auto-Einfügen an Cursorposition (an/aus)
- Floating Overlay (an/aus), `Overlay verschiebbar` (an/aus), Position zurücksetzen
- `Position zurücksetzen` ist immer verfügbar (auch bei deaktiviertem Verschiebe-Modus)
- Transkriptionssprache + Fallbacks
- Hotkey (Taste + Modifiers), Push-to-Talk
- Start bei Anmeldung
- LMM-Auswahlfenster mit Download nicht installierter Modelle

## Speicherorte (lokal)

- Verlauf (SQLite): `~/Library/Application Support/DictateFlow/history.sqlite`
- Temporäre Aufnahmen: `~/Library/Application Support/DictateFlow/Recordings`
- Empfohlener Modellordner: `~/Library/Application Support/DictateFlow/whisper-models`
- App-Icon-Assets: `DictateFlow/Resources/Assets.xcassets/AppIcon.appiconset`

Hinweis: Aufnahme-Dateien werden nach Verarbeitung wieder gelöscht.

## Datenschutz

- Keine Cloud-Transkription in dieser App-Logik
- Whisper läuft lokal
- Ollama läuft lokal
- Verlauf liegt lokal als SQLite

## Typische Fehler & Lösungen

### `whisper.cpp CLI wurde nicht gefunden`

- `whisper-cpp` installieren (`brew install whisper-cpp`)
- In Einstellungen `Whisper automatisch finden` klicken
- Oder Pfad manuell setzen (z. B. `/opt/homebrew/bin/whisper-cli`)

### `Whisper-Modell wurde nicht gefunden`

- Modell herunterladen (`ggml-*.bin`)
- Modellordner korrekt setzen
- In Einstellungen `Modellordner automatisch finden`

### `You don't have permission to save ... /usr/local/share/whisper`

- Nicht in `/usr/local/share/whisper` speichern
- User-schreibbaren Ordner verwenden: `~/Library/Application Support/DictateFlow/whisper-models`

### `Ollama-Ausführung fehlgeschlagen: env: ollama: No such file or directory`

- Ollama installieren (`brew install ollama`)
- In Einstellungen `Ollama automatisch finden`
- Pfad manuell prüfen (`/opt/homebrew/bin/ollama`)

### `could not connect to ollama server, run 'ollama serve'`

- App versucht den Server beim Start automatisch zu starten
- Falls nötig manuell starten:

```bash
ollama serve
```

- Danach App erneut testen

### `Bedienungshilfe wurde nicht freigegeben`

- Systemeinstellungen > Datenschutz & Sicherheit > Bedienungshilfen
- Aktiven DictateFlow-Eintrag erlauben
- Wenn mehrere Einträge vorhanden sind: alte entfernen, aktuellen erneut aktivieren
- Bei Xcode-Debug-Builds (DerivedData) kann sich der App-Pfad ändern
- In Xcode Signing mit Development Team setzen und neu starten
- Optional zurücksetzen:

```bash
tccutil reset Accessibility com.mesutoezciftci.DictateFlow
```

### `App-Icon wird nicht angezeigt`

- Sicherstellen, dass das Projekt frisch aus `project.yml` generiert wurde:

```bash
xcodegen generate
```

- In Xcode `Product > Clean Build Folder` ausführen und neu starten.
- Danach den `DerivedData`-Build erneut starten, damit `Assets.car` und `AppIcon.icns` neu erzeugt werden.

## Architektur (Datei-Übersicht)

- App Entry: `DictateFlow/DictateFlowApp.swift`
- Hauptlogik: `DictateFlow/Helpers/AppViewModel.swift`
- Audio: `DictateFlow/Managers/AudioRecorder.swift`
- Whisper: `DictateFlow/Managers/WhisperService.swift`
- Ollama: `DictateFlow/Managers/OllamaService.swift`
- Zwischenablage + Auto-Paste: `DictateFlow/Managers/ClipboardManager.swift`
- Overlay: `DictateFlow/Helpers/FloatingOverlayController.swift`
- Hotkeys: `DictateFlow/Helpers/HotkeyManager.swift`
- Setup-Assistent: `DictateFlow/Views/SetupWizardView.swift`, `DictateFlow/Helpers/SetupWizardViewModel.swift`
- Verlauf/SQLite: `DictateFlow/Helpers/HistoryStore.swift`
- Modelle: `DictateFlow/Models/*`
- Views: `DictateFlow/Views/*`

## Hinweise für Entwickler

- Das Xcode-Projekt wird aus `project.yml` generiert.
- Bei Änderungen an Source-Layout oder Build-Settings: `xcodegen generate` erneut ausführen.
- Debug-Build ohne Code Signing ist möglich (`CODE_SIGNING_ALLOWED=NO`), kann aber Accessibility-Verhalten beeinflussen.
