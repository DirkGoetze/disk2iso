<!--
# Copilot/KI-Policy

---

**HINWEIS:** Diese Datei ist die zentrale und einzig gültige Policy-Quelle für Copilot- und KI-Anweisungen im Projekt. Andere Versionen oder Kopien (z.B. im .github-Ordner oder Hauptordner) sind zu ignorieren und werden nicht mehr gepflegt.

---

## Kommunikationsrichtlinien - Prompt-Keywords

### #Frage - Analyse und Diskussion ohne Code-Änderungen

Wenn ein Prompt mit **#Frage** beginnt oder die Formulierung eine Frage impliziert:

- **Schreibweise**: Case-insensitive – `#Frage`, `#frage`, `#FRAGE` werden alle akzeptiert
- **Ziel**: Analyse durchführen, verschiedene Lösungsansätze vergleichen, Konzepte erklären
- **KEINE Code-Änderungen**: Es dürfen keine Dateien editiert, erstellt oder gelöscht werden
- **Erweiterte Analyse**: Think-Modus und gesamte Codebasis können genutzt werden
- **Antwort-Format**: Diskussion, Erklärung, Vor-/Nachteile, Optionen aufzeigen

**Signalwörter für #Frage-Modus:**
- "Was sind die Auswirkungen..."
- "Wie beeinflusst das..."
- "Was müssen wir bedenken..."
- "Macht das Sinn..."
- "Sollen wir..." / "Sollten wir..."

### #Analyse - Tiefgehende Code-Analyse mit Dokumentation

Wenn ein Prompt mit **#Analyse** beginnt:

- **Schreibweise**: Case-insensitive – `#Analyse`, `#analyse`, `#ANALYSE` werden alle akzeptiert
- **Ziel**: Detaillierte Analyse über gesamte Codebasis ohne Code-Änderungen
- **KEINE Code-Änderungen**: Es dürfen keine Dateien außer Dokumentation bearbeitet werden
- **Erweiterte Analyse**: Think-Modus nutzen für komplexe Zusammenhänge
- **Ergebnis-Optionen**:
  1. Detaillierte Auswertung im Chat
  2. Dokument im `todo/` Ordner (z.B. `todo/Analyse_Thema.md`)
  3. Einschätzung zur User-Interpretation
  4. 1-3 konkrete Lösungsansätze mit Vor-/Nachteilen

**Beispiele:**
- `#Analyse Provider-Abhängigkeiten im Metadata-Framework`
- `#Analyse Performance-Optimierung bei großen Disc-Sammlungen`
- `#Frage Wie wirkt sich Multi-Provider-Support auf die Ladeordnung aus?`

---

## disk2iso-spezifische Entwicklungsrichtlinien

### Provider-System Pattern

Bei der Entwicklung neuer Metadata-Provider ist folgendes Pattern einzuhalten:

```bash
# Provider-Registrierung (in Provider-Modul)
metadata_register_provider \
    "provider_name" \
    "disc-types" \
    "provider_query_function" \
    "provider_parse_function" \
    "provider_apply_function"

# Query-Funktion (Suche nach Metadata)
provider_query_function() {
    local search_term="$1"
    local output_file="$2"
    # API-Call und JSON-Response speichern
}

# Parse-Funktion (User-Auswahl verarbeiten)
provider_parse_function() {
    local selected_id="$1"
    local query_file="$2"
    # Extrahiere Metadata aus Query-Result
}

# Apply-Funktion (Setze disc_label)
provider_apply_function() {
    local metadata="$1"
    # Formatiere disc_label
}
```

### Variablen-Konventionen

**Runtime Globals (nicht readonly):**
```bash
# Framework-Variablen (zur Laufzeit initialisiert)
METADATA_CACHE_BASE=""
disc_label=""
disc_type=""
disc_id=""
```

**Assoziative Arrays:**
```bash
# Provider-Registrierung
declare -A METADATA_PROVIDERS
declare -A METADATA_QUERY_FUNCS
declare -A METADATA_PARSE_FUNCS
declare -A METADATA_APPLY_FUNCS

# Disc-Type Mapping
declare -A METADATA_DISC_PROVIDERS
```

**Readonly Constants:**
```bash
readonly DATA_DIR="data"
readonly TEMP_DIR=".temp"
readonly API_TIMEOUT=30
```

### Logging und Mehrsprachigkeit

Alle Module müssen die Sprachdatei laden:
```bash
# Lade Sprachdatei für dieses Modul
load_module_language "modulname"

# Verwende MSG_* Variablen
log_info "$MSG_PROVIDER_REGISTERED"
log_error "$MSG_QUERY_FAILED"
```

### API-Integration

Funktionen die vom Web-Frontend aufgerufen werden müssen JSON zurückgeben:
```bash
function_name() {
    # ... Logik ...
    
    # JSON-Response für API
    if [[ "$API_MODE" == "true" ]]; then
        echo "{\"status\":\"success\",\"data\":\"$result\"}"
        return 0
    fi
    
    # Standard-Output für CLI
    echo "$result"
}
```

---

## Code-Kommentar- und Dokumentationsstandard

Das folgende Schema für Funktionskommentare ist für alle Quellcodedateien im Projekt verbindlich – unabhängig von der Sprache (Bash, Python, JavaScript, HTML, CSS).

**Allgemeine Vorgaben:**

- Rahmenlinien bestehen immer aus 71 (Bash) bzw. 78 (andere Sprachen) Bindestrichen oder dem passenden Kommentarzeichen.
- Nach dem Funktionsnamen folgt eine Zeile mit der Beschreibung.
- Optional können weitere Details, Parameter, Rückgabewerte, Besonderheiten ergänzt werden.
- Die Einrückung und die Punkte/Doppelpunkte müssen im gesamten Projekt konsistent sein.
- Nach der Definition aller lokalen Variablen/Konstanten innerhalb der Funktion folgt immer eine Leerzeile, bevor der eigentliche Funktionscode beginnt.
- Für Shellskripte ist ausschließlich Bash-Syntax zu verwenden (keine SH-Kompatibilität oder Mischformen).

**Entscheidungsdokumentation:**

In Funktionsblöcken müssen alle relevanten Entscheidungen (z. B. Verzweigungen, Rückgabewerte, Fehlerbehandlung) durch strukturierte Kommentare dokumentiert werden. Die Kommentare sollen den Zweck der Entscheidung, die möglichen Alternativen und deren Auswirkungen auf den Programmablauf kurz erläutern. Dies gilt insbesondere für Kontrollstrukturen wie if/else, case, Schleifen und Fehlerbehandlungen.

**Beispiele für verschiedene Sprachen:**

_Bash (disk2iso Standard):_
```bash
# Funktion: Registriere Metadata-Provider
# Parameter: $1 = provider_name (z.B. "musicbrainz", "tmdb")
#            $2 = disc_types (komma-separiert: "audio-cd" oder "dvd-video,bd-video")
#            $3 = query_function (Name der Query-Funktion)
#            $4 = parse_function (Name der Parse-Funktion)
#            $5 = apply_function (Name der Apply-Funktion, optional)
# Rückgabe: 0 = Erfolg, 1 = Fehler
metadata_register_provider() {
    local provider="$1"
    local disc_types="$2"
    local query_func="$3"
    local parse_func="$4"
    local apply_func="${5:-metadata_default_apply}"
    
    # Validierung
    if [[ -z "$provider" ]] || [[ -z "$disc_types" ]]; then
        log_error "$MSG_INVALID_PARAMETERS"
        return 1
    fi
    
    # (weitere Implementierung)
}
```

_Bash (Legacy-Style, noch zu migrieren):_
```bash
install_package() {
    # -----------------------------------------------------------------------
    # install_package
    # -----------------------------------------------------------------------
    # Funktion,: Installiert ein einzelnes Systempaket in gewünschter Version
    # .........  (optional, prüft Version und installiert ggf. gezielt)
    # Rückgabe.: 0 = OK
    # .........  1 = Fehler
    # .........  2 = Version installiert, aber nicht passend
    # Parameter: $1 = Paketname
    # .........  $2 = Version (optional)
    # Extras...: Nutzt apt-get, prüft nach Installation erneut
    local pkg="$1"
    local version="$2"

    # (ab hier Funktionscode)
}
```

_Python:_
```python
# ----------------------------------------------------------------------------
# def take_photo
# ----------------------------------------------------------------------------
# Funktion: Löst die Kamera aus und speichert das Foto im Zielverzeichnis
# Parameter: filename (str) – Zielpfad für das Foto
# Rückgabe: Pfad zur gespeicherten Datei oder None bei Fehler
# Extras...: Platzhalter für Hardwarezugriff, Logging integriert

def take_photo(filename):
    # ... Funktionscode ...
    pass
```

_JavaScript:_
```js
// ------------------------------------------------------------------------------
// function showGallery
// ------------------------------------------------------------------------------
// Funktion: Zeigt die Fotogalerie im Frontend an
// Parameter: images (Array) – Liste der Bildpfade
// Rückgabe: void
// Extras...: Baut das DOM dynamisch auf
function showGallery(images) {
    // ... Funktionscode ...
}
```

_HTML (für größere Funktionsblöcke/Skripte):_
```html
<!-- -------------------------------------------------------------------------- -->
<!-- gallery-section -->
<!-- -------------------------------------------------------------------------- -->
<!-- Funktion: Zeigt die Galerie mit allen aufgenommenen Fotos an
     Extras...: Wird per JavaScript dynamisch befüllt -->
<section id="gallery-section">
    <!-- ... HTML-Inhalt ... -->
</section>
```

_CSS (für größere Block-Kommentare):_
```css
/* -----------------------------------------------------------------------------
   .gallery-grid
   -----------------------------------------------------------------------------
   Funktion: Layout für die Fotogalerie im Grid-Stil
   Extras...: Responsiv, mit flex-wrap
*/
.gallery-grid {
    /* ... CSS-Regeln ... */
}
```

---

## Review- und Änderungs-Policy

### Copilot Review Policy für Quellcodedateien (Bash, Python, HTML, CSS, JS, ...)

- Prüfe Syntax und Ausführung bzw. Funktionalität für alle relevanten Modi (z.B. Installation, Update, Deinstallation, Laufzeit, Interaktion)
- Suche nach möglichen Fehlerquellen und Schwierigkeiten, die eine korrekte Ausführung oder Darstellung verhindern könnten (z.B. Rechte, Konfigurationskonsistenz, Abhängigkeiten, veraltete Software, Distributionen, Hardware, Browser-Kompatibilität)
- **disk2iso-spezifisch**: Prüfe Provider-Registrierung, API-Kompatibilität, State-Management, Mehrsprachigkeit
- Liste alle gefundenen Fehler und Schwachstellen auf
- Schlage für jeden gefundenen Punkt eine Korrektur vor und begründe diese
- Nach Nutzer-Zustimmung wird jede Anpassung einzeln und nachvollziehbar vorgenommen
- Ziel: Ein robustes, auf allen aktuellen Debian- und Ubuntu-Systemen (und Derivaten) sowie gängigen Browsern funktionierendes Projekt mit minimalen Hardware-Anforderungen
- Für Shellskripte gilt: Nur Bash-Syntax und -Funktionen prüfen und verwenden, keine SH-Mischformen
- **Assoziative Arrays**: Prüfe korrekte Deklaration mit `declare -A` vor Verwendung
- **JSON-Handling**: Alle API-Funktionen müssen valides JSON zurückgeben

#### Dialogorientierte Copilot-Funktionsprüfung (Review-Workflow)

1. Bei jeder Chat-Eingabe mit der Vorgabe „Prüfe jede Funktion: [Vorgabe]“ analysiert Copilot jede betroffene Funktion einzeln.
2. Für jede Funktion wird der Analyse- und Änderungsvorschlag einzeln präsentiert und mit dem Nutzer abgestimmt.
3. Nach Nutzerentscheidung wird für jede Funktion eine der folgenden Optionen umgesetzt:
   a) Änderungen werden direkt in den Code übernommen.
   b) Änderungen werden als TODO-Block in die Funktion eingetragen.
   c) Änderungen werden verworfen (keine Anpassung).
4. Dieser dialogorientierte Review-Prozess ist für alle Copilot-/KI-gestützten Funktionsprüfungen im gesamten Projekt verbindlich.

- Achte bei Markdown-Dateien auf korrekte Formatierung:
  - Überschriften (z.B. # Titel) immer mit Leerzeile davor und danach
  - Listen immer mit Leerzeile davor und danach
  - Nur eine H1-Überschrift pro Datei
  - Jede Datei muss mit einer Leerzeile enden
  - Keine doppelten Überschriften oder Listen ohne Abstand
  - Siehe DOKUMENTATIONSSTANDARD.md und https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md

---

## Policy: Erhalt von Funktionskommentaren und Kontrollstruktur-Kommentaren

- Bei automatischen oder KI-gestützten Codeänderungen dürfen bestehende Funktionskommentare, Blockkommentare und erläuternde Kommentare zu Kontrollstrukturen (z.B. Hinweise auf entfernte Interaktivität, Parameterübergabe, Schleifenlogik) nicht entfernt oder verkürzt werden.
- Kommentare, die die ursprüngliche oder geänderte Logik für Menschen nachvollziehbar machen (z.B. warum eine Schleife entfernt wurde, wie Parameterübergabe statt Benutzereingabe funktioniert), sind stets zu erhalten und ggf. zu aktualisieren.
- Automatisierte Refaktorierungen müssen sicherstellen, dass alle erklärenden Kommentare zu Funktionsschnittstellen, Parametern, Rückgabewerten und Besonderheiten (wie ausgelagerte Interaktivität) erhalten bleiben.
- Bei Änderungen an Funktionssignaturen oder -logik ist der Kommentarblock entsprechend zu aktualisieren, aber niemals zu entfernen oder zu verkürzen.
- Diese Regel gilt für alle Sprachen und alle Quellcodedateien im Projekt.

---

## Policy: Rückgabewerte und Fehlercodes

- 0 = OK
- 1 = Allgemeiner Fehler
- 2 = Konfigurationsfehler
- 3 = Backup-Fehler
- 4 = Reload-Fehler
- 10+ = Interaktive/sonstige Fehlerfälle
Die Rückgabewerte sind in allen Funktionskommentaren und der Implementierung konsistent zu verwenden

## Policy: Rückgabewert-Codierung nach Fehler-Schwere

Für alle Skripte und Funktionen im Projekt gilt folgende verbindliche Skala für Rückgabewerte:

| Wert | Bedeutung                                                                 |
|------|--------------------------------------------------------------------------|
| 0    | OK (kein Fehler)                                                        |
| 1    | Kritischer Fehler (System nicht funktionsfähig, Datenverlust, Sicherheit)|
| 2    | Schwerer Fehler (z.B. Konfigurationsfehler, Dienst nicht startbar)       |
| 3    | Backup-Fehler (Datenintegrität gefährdet, System läuft weiter)           |
| 4    | Reload-Fehler (Konfigurationsänderung nicht aktiv, System läuft weiter)  |
| 5    | Funktionsfehler (Teilfunktion schlägt fehl, Hauptfunktion läuft)         |
| 6    | Warnung (z.B. veraltete Konfiguration, keine unmittelbare Auswirkung)    |
| 7    | Nicht-kritischer Fehler (temporäre Störung, Wiederholung möglich)        |
| 8    | Hinweis/Info (z.B. optionale Funktion nicht verfügbar)                   |
| 9    | Geringfügige Abweichung (kosmetische Fehler, keine Auswirkung)           |
| 10+  | Interaktive/Sonderfälle (z.B. Benutzerabbruch, Symlink-Fehler, Sonstiges)|

- Die Rückgabewerte sind in allen Funktionskommentaren und der Implementierung konsistent zu verwenden.
- Bei neuen Funktionen ist diese Skala strikt einzuhalten.
- Bei bestehenden Funktionen sind Abweichungen zu dokumentieren und mittelfristig zu beheben.
- Ziel ist eine eindeutige, priorisierbare Fehlerauswertung und einheitliche Fehlerbehandlung im gesamten Projekt.

---
