# Python Umstellung

Ziel: Auflistung aller Python-Funktionen mit Kurzbeschreibung, Funktionslogik und Kennzeichnung, ob Business-Logik vorhanden ist, die nach Bash portiert werden sollte.

Hinweis: In app.py sind mehrere Funktionen doppelt definiert (z.B. get_os_info). In Python ueberschreibt die spaetere Definition die fruehere.

## services/disk2iso-web/app.py

- get_settings: Baut ein Settings-Dict aus mehreren Config-Werten (inkl. Typkonvertierung und Modul-Flags). Business-Logik: Ja (Konsolidierung und Defaults).
- get_service_status_detailed: Fragt systemd Status, mappt auf Status-Objekt. Business-Logik: Ja (Status-Mapping).
- get_disk_space: Ermittelt freien/gesamten Speicher per statvfs und berechnet Prozente. Business-Logik: Ja (Berechnung).
- count_iso_files: Zaehlt ISO-Dateien rekursiv im Output-Verzeichnis. Business-Logik: Ja (Archiv-Scan).
- get_iso_files_by_type: Rekursiver Scan nach ISOs, sammelt Metadaten/Thumbnails und ordnet Typen zu. Business-Logik: Ja (Archiv-Scan + Typ-Erkennung).
- get_live_status: Liest status/attributes/progress JSON und normalisiert Daten (Audio-CD Sonderfall). Business-Logik: Ja (Status-Normalisierung).
- get_status_text: Leitet einen menschlichen Status-Text aus Live-Status, Service-Status und MusicBrainz-Selection ab. Business-Logik: Ja (Status-Entscheidungen).
- index: Baut Daten fuer die Startseite (Status, Archiv-Counts, Disk-Space). Business-Logik: Ja (Aggregation und Counts).
- api_modules: Liest Modul-Enabled-Status aus INI-Dateien, gibt Modul-Map zurueck. Business-Logik: Ja (Konfigurations-Entscheidung).
- api_status: Aggregiert Status-Daten inkl. Archiv-Counts. Business-Logik: Ja (Aggregation + Counts).
- api_archive_thumbnail: Sucht Thumbnail im Output-Verzeichnis und liefert Datei. Business-Logik: Ja (Dateiscan).
- browse_directories: Listet Verzeichnisse und prueft Berechtigungen. Business-Logik: Ja (Filesystem-Logik).
- api_logs_current: Liest neueste Log-Datei aus .log und liefert letzte Zeilen. Business-Logik: Ja (Dateiscan + Auswahl).
- api_logs_archived: Listet Log-Dateien in .log. Business-Logik: Ja (Dateiscan).
- api_logs_archived_file: Liest eine Log-Datei und liefert letzte Zeilen. Business-Logik: Ja (Dateizugriff + Auswahl).
- get_os_info (spaete Definition): Ruft Bash OS-Info auf, fallback mit Default-Objekt. Business-Logik: Ja (Fallback-Objekt).
- get_storage_info (spaete Definition): Ruft Bash Storage-Info auf, fallback mit Default-Objekt. Business-Logik: Ja (Fallback-Objekt).
- get_archiv_info (spaete Definition): Ruft Bash Archiv-Info auf, fallback mit Default-Objekt. Business-Logik: Ja (Fallback-Objekt).
- get_software_info (spaete Definition): Ruft Bash Software-Info auf, fallback mit Default-Objekt. Business-Logik: Ja (Fallback-Objekt).
- api_tmdb_search: Fuehrt TMDB Suche aus, verarbeitet Raw-Response, lädt Poster, baut Ergebnisstruktur. Business-Logik: Ja (Kern-Logik).
- api_tmdb_apply: Wendet TMDB-Metadaten an, optionales ISO-Rename. Business-Logik: Ja (Workflow + Rename).
- api_musicbrainz_search: Optionales ISO-Mount zum Track-Count, Bash-Suche, JSON-Parsing. Business-Logik: Ja (Workflow + Track-Count).
- api_musicbrainz_apply: Fuehrt Remastering aus und liefert Ergebnis. Business-Logik: Ja (Workflow).

## services/disk2iso-web/i18n.py

- read_config_language: Liest LANGUAGE aus disk2iso.conf durch eigenes File-Parsing. Business-Logik: Ja (Config-Parsing).
- _load_lang_file: Parst Bash-Sprachdateien in MSG_* Mappings. Business-Logik: Ja (Parsing).
- load_web_translations: Laedt Web- und Backend-Lang-Files, priorisiert Web-Texte. Business-Logik: Ja (Merge-Logik).
- get_translations: Liefert Uebersetzungen, inkl. Default-Logik. Business-Logik: Ja (Fallback-Entscheidung).

## services/disk2iso-web/routes/__init__.py

- (keine Funktionen definiert)

## services/disk2iso-web/routes/widgets/archiv_systeminfo.py


## services/disk2iso-web/routes/widgets/status_disk2iso.py


## services/disk2iso-web/routes/widgets/status_disk2iso_web.py


## services/disk2iso-web/routes/widgets/settings_common.py

- get_common_settings: Liest DDRESCUE_RETRIES via libsettings.sh und konvertiert nach int. Business-Logik: Ja (Typ-Default).

## services/disk2iso-web/routes/widgets/settings_config.py

- get_config_settings: Liest DEFAULT_OUTPUT_DIR via libsettings.sh und setzt Default. Business-Logik: Ja (Default-Logik).
- browse_directories: Listet Unterverzeichnisse und prueft Berechtigungen. Business-Logik: Ja (Filesystem-Logik).

## services/disk2iso-web/routes/widgets/settings_drivestat.py

- get_drivestat_settings: Liest USB Detection Settings via libsettings.sh und konvertiert nach int. Business-Logik: Ja (Typ-Default).

## services/disk2iso-web/routes/widgets/sysinfo_systeminfo.py


## services/disk2iso-web/routes/widgets/outputdir_systeminfo.py


## services/disk2iso-web/routes/widgets/softwarecheck_systeminfo.py

- api_softwarecheck: Flacht Software-Dict in Liste fuer Frontend. Business-Logik: Ja (Mapping-Logik).

## services/disk2iso-web/routes/widgets/dependencies_systeminfo.py

- api_dependencies: Flacht Software-Dict in Liste fuer Frontend. Business-Logik: Ja (Mapping-Logik).

## Deprecated (keine aktuellen Aufrufe im Web-Frontend/Code gefunden)

- api_musicbrainz_select: Schreibt Selection-JSON fuer MusicBrainz. Business-Logik: Ja (Status-Workflow). **VERALTET - Nicht verwendet.**
- get_command_version: Fuehrt Kommando aus und extrahiert Versionsstring via Regex. Business-Logik: Ja (Version-Parsing). **VERALTET - Nicht verwendet.**
- get_package_version: Liest dpkg Status und parst Version. Business-Logik: Ja (Version-Parsing). **VERALTET - Nicht verwendet.**
- get_available_package_version: Liest apt-cache policy und parst Candidate Version. Business-Logik: Ja (Version-Parsing). **VERALTET - Nicht verwendet.**
- check_software_versions: Aggregiert Softwareliste, kombiniert installierte/available Versionen und Update-Status. Business-Logik: Ja (Abhaengigkeits-Analyse). **VERALTET - Nicht verwendet.**
- get_disk2iso_info: Sammelt Service-Status, Install-Pfad und Python-Version. Business-Logik: Ja (Status-Entscheidung). **VERALTET - Nicht verwendet.**
- get_software_list_from_system_json: Mappt system.json-Dict auf Frontend-Liste. Business-Logik: Ja (Mapping-Logik). **VERALTET - Nicht verwendet.**

## In Module verschoben (Modulare Architektur)

- api_metadata_pending: **VERSCHOBEN** zu modulspezifischen Endpoints:
  - `/api/metadata/musicbrainz/pending` in disk2iso-musicbrainz/www/routes/api_musicbrainz.py
  - `/api/metadata/tmdb/pending` in disk2iso-tmdb/www/routes/api_tmdb.py
  - Rufen Bash-Funktionen auf: `musicbrainz_get_cached_queries()` und `tmdb_get_cached_queries()`
  
- api_metadata_select: **ENTFERNT UND ERSETZT** durch modulspezifische Endpoints:
  - `/api/metadata/musicbrainz/select` in disk2iso-musicbrainz/www/routes/api_musicbrainz.py
  - `/api/metadata/tmdb/select` in disk2iso-tmdb/www/routes/api_tmdb.py
  - Neue Implementierung: Ruft direkt `musicbrainz_parse_selection()` bzw. `tmdb_parse_selection()` auf
  - Diese Bash-Funktionen schreiben Metadaten via `metadata_set_data()` und `metadata_set_info()` direkt in DISC_INFO/DISC_DATA Arrays
  - Eliminiert .mbselect/.tmdbselect Dateien - Daten fließen direkt in zentrale Arrays

- api_musicbrainz_manual: Schreibt manuelle Metadata JSON. Business-Logik: Ja (Status-Workflow). **AKTIV - Wird von MusicBrainz-Modul verwendet.**

- api_tmdb_select: Schreibt TMDB Selection JSON. Business-Logik: Ja (Status-Workflow). **AKTIV - Wird von TMDB-Modul verwendet.**

---

## TMDB Workflow-Analyse (Aktuelle Codebasis)

### Workflow-Übersicht: Service-Zeit (Disc eingelegt → Kopieren → .nfo)

| # | Workflow-Schritt | libdvd/libbluray | libmetadata | libtmdb | api_tmdb.py | tmdb-modal.js | Status |
|---|------------------|------------------|-------------|---------|-------------|---------------|--------|
| 1 | **Disc erkannt** | `dvd_detect_disc()`<br/>`bluray_detect_disc()` | - | - | - | - | ✅ |
| 2 | **Metadata Provider registriert** | - | Provider-Arrays<br/>`METADATA_QUERY_FUNCS[]` | `init_tmdb_provider()`<br/>registriert `tmdb_query` | - | - | ✅ |
| 3 | **Query starten** | - | `metadata_query_before_copy()`<br/>→ ruft Provider-Funktion | - | - | - | ✅ |
| 4 | **.tmdbquery erstellen** | - | - | `tmdb_query()`<br/>schreibt `.tmdbquery` | - | - | ✅ |
| 5 | **Pending prüfen** | - | - | `tmdb_get_cached_queries()` | `/api/metadata/tmdb/pending`<br/>ruft Bash-Funktion | - | ⚠️ STUB |
| 6 | **Modal laden** | - | - | - | - | Pollt `/pending`<br/>Zeigt Modal | ✅ |
| 7 | **User wählt aus** | - | - | - | - | POST `/select` | ✅ |
| 8 | **Auswahl speichern** | - | `metadata_set_data()`<br/>`metadata_set_info()` | `tmdb_parse_selection()`<br/>→ DISC_INFO/DISC_DATA | `/api/metadata/tmdb/select`<br/>ruft Bash-Funktion | - | ✅ |
| 9 | **Warte auf Auswahl (alt)** | - | `metadata_wait_for_selection()`<br/>Loop + `.tmdbselect` | - | - | - | ❌ DEPRECATED |
| 10 | **Kopiervorgang** | `dvd_copy_disco()`<br/>`bluray_copy()` | - | - | - | - | ✅ |
| 11 | **.nfo erstellen** | - | `metadata_export_nfo()`<br/>→ `_metadata_export_video_nfo()` | - | - | - | ✅ |

### Workflow-Übersicht: Archiv-Nachbearbeitung (Optional, ISO bereits vorhanden)

| # | Workflow-Schritt | libmetadata | libtmdb | app.py (alt) | Frontend (alt) | Status |
|---|------------------|-------------|---------|--------------|----------------|--------|
| 12 | **ISO aus Archiv wählen** | - | - | - | archive.html | ✅ |
| 13 | **Metadata laden** | - | `.tmdbquery` existiert noch | `api_tmdb_search()`<br/>→ `search_and_cache_tmdb()` | `tmdb.js` | ❌ NICHT EXISTIERT |
| 14 | **Modal anzeigen** | - | - | - | `tmdb.js` | ❌ DISABLED |
| 15 | **User wählt** | - | - | `api_tmdb_select()`<br/>→ `tmdb_selection.json` | `tmdb.js` | ❌ UNGENUTZT |
| 16 | **.nfo überschreiben** | - | - | `api_tmdb_apply()`<br/>→ `add_metadata_to_existing_iso()` | - | ❌ NICHT EXISTIERT |

### Status-Legende

- ✅ **Implementiert** - Funktion existiert und ist funktionsfähig
- ⚠️ **STUB** - Funktions-Stub existiert, muss noch implementiert werden
- ❌ **FEHLT** - Funktion existiert nicht oder ruft nicht-existierende Abhängigkeiten auf
- ❌ **DEPRECATED** - Alte Implementierung, wird ersetzt
- ❌ **DISABLED** - Im Code vorhanden aber deaktiviert

### Handlungsbedarf

**Fehlende Implementierungen (Service-Zeit):**
1. `tmdb_get_cached_queries()` - aktuell nur Stub in [libtmdb.sh](l:/clouds/onedrive/Dirk/projects/disk2iso-tmdb/lib/tmdb_get_cached_queries.sh.stub)

**Zu entfernender Code (Archiv-Nachbearbeitung defekt):**
1. ❌ `api_tmdb_search()` in app.py:1919 - ruft nicht-existierende `search_and_cache_tmdb()`
2. ❌ `api_tmdb_select()` in app.py:1211 - schreibt ungenutztes `tmdb_selection.json`
3. ❌ `api_tmdb_apply()` in app.py:2074 - ruft nicht-existierende `add_metadata_to_existing_iso()`
4. ❌ `tmdb.js` - bereits disabled, kann entfernt werden

**Fehlende Archiv-Nachbearbeitung (falls gewünscht):**
- Endpoint: `/api/metadata/tmdb/reload?iso_path=...` - lädt vorhandene `.tmdbquery` und zeigt Modal
- Endpoint: `/api/metadata/tmdb/apply` - ruft `metadata_export_nfo()` für bestehendes ISO
- Wiederverwendung von tmdb-modal.js (bereits vorhanden)

**Empfehlung:**
1. Implementiere `tmdb_get_cached_queries()` für Service-Zeit-Workflow
2. Entferne defekten Archiv-Code (api_tmdb_search, api_tmdb_select, api_tmdb_apply, tmdb.js)
3. Später: Neue Archiv-Nachbearbeitung auf Basis der `.tmdbquery` Dateien implementieren (wiederverwendet bestehende Komponenten)
