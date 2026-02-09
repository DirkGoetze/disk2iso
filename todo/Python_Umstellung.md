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

- api_musicbrainz_select: Schreibt Selection-JSON fuer MusicBrainz. Business-Logik: Ja (Status-Workflow).
- api_musicbrainz_manual: Schreibt manuelle Metadata JSON. Business-Logik: Ja (Status-Workflow).
- api_tmdb_select: Schreibt TMDB Selection JSON. Business-Logik: Ja (Status-Workflow).
- api_metadata_pending: Sucht .mbquery/.tmdbquery Dateien, berechnet Timeout und liefert Pending-Info. Business-Logik: Ja (Workflow + Timeout).
- api_metadata_select: Schreibt .mbselect/.tmdbselect Dateien auf Basis der Auswahl. Business-Logik: Ja (Workflow).
- get_command_version: Fuehrt Kommando aus und extrahiert Versionsstring via Regex. Business-Logik: Ja (Version-Parsing).
- get_package_version: Liest dpkg Status und parst Version. Business-Logik: Ja (Version-Parsing).
- get_available_package_version: Liest apt-cache policy und parst Candidate Version. Business-Logik: Ja (Version-Parsing).
- check_software_versions: Aggregiert Softwareliste, kombiniert installierte/available Versionen und Update-Status. Business-Logik: Ja (Abhaengigkeits-Analyse).
- get_disk2iso_info: Sammelt Service-Status, Install-Pfad und Python-Version. Business-Logik: Ja (Status-Entscheidung).
- get_software_list_from_system_json: Mappt system.json-Dict auf Frontend-Liste. Business-Logik: Ja (Mapping-Logik).
