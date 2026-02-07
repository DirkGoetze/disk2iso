# disk2iso Module Store

Dieser Ordner enthält die Manifest-Dateien für den disk2iso Module Store.

## Struktur

```
store/
├── catalog.json           # Master-Katalog mit Übersicht aller Module
├── core.json             # Manifest für disk2iso Core
└── README.md             # Diese Datei
```

Jedes Modul-Repository hat ebenfalls einen `store/` Ordner mit seinem Manifest:
- `disk2iso-audio/store/audio.json`
- `disk2iso-dvd/store/dvd.json`
- `disk2iso-bluray/store/bluray.json`
- `disk2iso-metadata/store/metadata.json`
- `disk2iso-mqtt/store/mqtt.json`
- `disk2iso-musicbrainz/store/musicbrainz.json`
- `disk2iso-tmdb/store/tmdb.json`

## Verwendung

### Test-Setup (1&1 Web-Server)

Für Tests kann der `base_url` in `catalog.json` auf deinen 1&1-Server zeigen:

```json
{
  "base_url": "https://dein-server.1und1.de/disk2iso-store"
}
```

### Produktion (GitHub)

Für die Produktion werden die Manifests direkt von GitHub geladen:

```json
{
  "modules": {
    "audio": {
      "manifest_url": "https://raw.githubusercontent.com/Disk2ISO/disk2iso-audio/main/store/audio.json"
    }
  }
}
```

## Kategorien

- **core**: Hauptsystem (disk2iso Core)
- **optional**: Optionale Module (Audio, DVD, Blu-ray, Metadata, MQTT)
- **providers**: Metadata-Provider (MusicBrainz, TMDB)

## Manifest-Schema

Jedes Modul-Manifest enthält:

- `id`: Eindeutige Modul-ID
- `name`: Anzeigename
- `category`: Kategorie (core/optional/providers)
- `description`: Beschreibung
- `requires`: Abhängigkeiten (z.B. `{"disk2iso": ">=1.3.0"}`)
- `current_version`: Aktuelle Version
- `versions[]`: Liste aller Versionen mit Download-URLs und Checksummen
- `features[]`: Liste der Features
- `install_method`: Installationsmethode (unzip/tar)
- `install_path`: Zielpfad
- `post_install[]`: Befehle nach Installation

## Web-Server Struktur (für lokale Tests)

```
disk2iso-store/
├── catalog.json
├── modules/
│   ├── core.json
│   ├── audio.json
│   └── ...
├── releases/          # Nur für Tests - Produktion nutzt GitHub Releases
│   ├── audio/
│   │   └── v1.3.0/
│   │       ├── audio-module.zip
│   │       └── audio-module.zip.sha256
│   └── ...
└── icons/            # Optional
    ├── core.svg
    └── ...
```

## Update-Workflow

1. Neue Version in Modul erstellen
2. GitHub Release mit `[modul]-module.zip` erstellen
3. Modul-Manifest (`store/[modul].json`) aktualisieren
4. Änderungen per `git push` veröffentlichen
5. Web-UI lädt automatisch aktualisierte Manifests

## Konfiguration im Web-UI

```ini
# conf/libcommon.ini
[store]
catalog_url=https://raw.githubusercontent.com/Disk2ISO/disk2iso/main/store/catalog.json
```
