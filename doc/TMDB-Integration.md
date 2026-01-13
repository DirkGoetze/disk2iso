# TMDB API Integration - Test-Dokumentation

## Übersicht

Die TMDB (The Movie Database) API-Integration wurde erfolgreich implementiert und ermöglicht automatische Film-Metadaten und Poster für DVD/Blu-ray ISOs.

## Implementierte Komponenten

### 1. Backend (Bash)

**lib/lib-dvd-metadata.sh** - Neue Bibliothek für TMDB-Integration:
- `search_tmdb_movie()` - Film in TMDB API suchen
- `search_tmdb_tv()` - TV-Serie in TMDB API suchen (v1.2.0+)
- `get_tmdb_movie_details()` - Details inkl. Credits abrufen
- `get_tmdb_tv_details()` - TV-Serien Details mit Creator abrufen (v1.2.0+)
- `download_tmdb_poster()` - Poster von TMDB herunterladen
- `create_movie_nfo()` - .nfo Datei für DVD/Blu-ray erstellen
- `select_tmdb_movie()` - Interaktive Filmauswahl (wartet auf Web-UI)
- `select_tmdb_content()` - Film/TV-Serie Auswahl mit Type-Selection Modal (v1.2.0+)
- `create_dvd_archive_metadata()` - Hauptfunktion für Metadaten-Erstellung
- `extract_movie_title()` - Filmtitel aus disc_label extrahieren

**Integrationen:**
- `lib/lib-dvd.sh` - copy_video_dvd() und copy_video_dvd_ddrescue() rufen Metadaten-Funktion auf
- `lib/lib-bluray.sh` - copy_bluray_ddrescue() ruft Metadaten-Funktion auf
- `disk2iso.sh` - Lädt lib-dvd-metadata.sh nach lib-dvd.sh
- `lib/config.sh` - Neue Variable TMDB_API_KEY

### 2. Frontend (Web-Interface)

**www/app.py** - API-Endpoints:
- `GET /api/tmdb/results` - TMDB-Suchergebnisse abrufen (Filme + TV-Serien)
- `POST /api/tmdb/select` - Film/TV-Serie auswählen
- `POST /api/tmdb/type` - Content-Type festlegen (movie/tv) (v1.2.0+)
- `POST /api/config` - TMDB_API_KEY speichern
- `GET /api/config` - TMDB_API_KEY laden

**www/templates/config.html** - Einstellungs-Seite:
- TMDB API-Key Eingabefeld
- Link zur Anleitung (TMDB-API-Key.md)

**www/templates/base.html** - Modals:
- TMDB Film/TV-Serien-Auswahl Modal
- TMDB Type-Selection Modal (Film vs. TV-Serie) (v1.2.0+)
- Script-Import für tmdb.js

**www/static/js/tmdb.js** - Film/TV-Auswahl:
- Automatisches Polling für TMDB-Ergebnisse
- Type-Selection Modal (Film vs. TV-Serie) bei mehrdeutigem Content (v1.2.0+)
- Modal-Anzeige mit Movie/TV-Cards
- Film/TV-Serie Auswahl per Klick
- Benachrichtigungen

**www/static/js/archive.js** - Archiv-Ansicht:
- Unterstützung für dvd-video und bd-video Metadaten
- Anzeige: Titel, Regisseur, Jahr, Genre, Laufzeit, Rating
- DVD/Blu-ray Placeholder-Fallback

**www/static/css/style.css** - Styles:
- `.movie-card` - Grid-Layout für Filmauswahl
- `.movie-poster`, `.movie-info` - Card-Komponenten
- `.notification` - Erfolgs/Fehler-Meldungen
- `.modal-large` - Größeres Modal für Filmliste

**www/static/img/dvd-placeholder.svg/png** - Placeholder:
- Blau-grauer Gradient-Hintergrund
- Disc-Illustration mit Reflektionen
- Clapperboard-Icon (Filmklappe)
- 250x250px, 12KB PNG

### 3. Dokumentation

**doc/TMDB-API-Key.md** - Anleitung:
- Account-Erstellung auf themoviedb.org
- API-Key-Beschaffung (Developer-Type, API-Key v3)
- Konfiguration (Web-UI + manuell)
- API-Limits (40 req/10s, ~2 req/Film)
- Troubleshooting
- Privacy & Legal

**doc/Handbuch.md** - Update:
- TMDB-API-Key.md als Abschnitt 6 verlinkt

## Funktionsweise

### Workflow bei DVD/Blu-ray Ripping:

1. **ISO-Erstellung**: DVD/Blu-ray wird mit copy_video_dvd() oder copy_bluray_ddrescue() gerippt
2. **Titel-Extraktion**: disc_label wird bereinigt (z.B. "the_matrix_1999" → "The Matrix")
3. **TMDB-Suche**: search_tmdb_movie() sendet API-Request
4. **Ergebnis-Verarbeitung**:
   - **1 Ergebnis**: Automatische Auswahl
   - **Mehrere Ergebnisse**: Warten auf Web-UI Auswahl (max 5 Min)
5. **Details abrufen**: get_tmdb_movie_details() mit Credits für Regisseur
6. **Metadaten erstellen**:
   - `.nfo` Datei mit TITLE, YEAR, DIRECTOR, GENRE, RUNTIME, RATING, TYPE, OVERVIEW
   - `-thumb.jpg` Poster (w500 von TMDB)
7. **Archiv-Integration**: Archive-Ansicht zeigt Metadaten mit Cover

### .nfo Format (DVD/Blu-ray):

```
TITLE=The Matrix
YEAR=1999
DIRECTOR=Lana Wachowski
GENRE=Action, Science Fiction
RUNTIME=136
RATING=8.2
TYPE=dvd-video
OVERVIEW=Set in the 22nd century, The Matrix tells...
```

## Test-Szenarien

### Manuelle Tests (nach API-Key-Konfiguration):

1. **DVD mit eindeutigem Titel**:
   - Disc einlegen mit klarem Label (z.B. "avatar_2009")
   - Erwartung: Automatische Auswahl, Metadaten ohne Modal

2. **DVD mit mehrdeutigem Titel**:
   - Disc mit generischem Label (z.B. "matrix")
   - Erwartung: Type-Selection Modal (Film vs. TV-Serie), dann TMDB-Modal mit Auswahlmöglichkeiten

2a. **TV-Serien DVD**:
   - Disc mit Serien-Label (z.B. "breaking_bad_s01")
   - Erwartung: Type-Selection Modal → TV-Serie auswählen → TMDB-Modal mit Serien-Ergebnissen

3. **Blu-ray Test**:
   - Blu-ray einlegen
   - Erwartung: TYPE=bd-video in .nfo, sonst identisch zu DVD

4. **Fehlende Konfiguration**:
   - TMDB_API_KEY leer lassen
   - Erwartung: Metadaten-Funktion wird übersprungen (kein Fehler)

5. **Archiv-Ansicht**:
   - Nach Metadaten-Erstellung /archive aufrufen
   - Erwartung: Film-Poster, Titel, Regisseur, Jahr, Genre, Rating angezeigt

### API-Limits beachten:

- **40 Requests / 10 Sekunden** (TMDB v3 Free Tier)
- Pro Film: ~2 Requests (1x Search, 1x Details)
- Bei Batch-Ripping Pause einbauen

## Bekannte Einschränkungen

1. **Sprache**: Aktuell hardcoded auf `de-DE` (deutsche Titel/Overviews)
2. **Timeout**: Film/TV-Auswahl-Wartezeit 5 Minuten (konfigurierbar in lib-dvd-metadata.sh)
3. **Titel-Extraktion**: Funktioniert am besten mit sauberen Labels (Unterstriche, Jahr am Ende)
4. **TV-Serien**: Kein automatisches Staffel/Episoden-Mapping (nur Serie als Ganzes)

## Zukünftige Erweiterungen

- [ ] Multi-Language Support (Sprachauswahl in Config)
- [ ] TV-Serien Staffel/Episoden-Mapping (Season/Episode-Level Metadaten)
- [ ] Backdrop-Images zusätzlich zu Postern
- [ ] Cast-Informationen in .nfo
- [ ] Metadaten-Nachbearbeitung (Edit-Funktion im Web-UI)
- [ ] Batch-Metadaten-Regenerierung (nachträgliche Erfassung, wie bei Audio-CDs)

## Changelog

**13.01.2026 - v1.2.0**
- ✅ TMDB API-Integration für DVD/Blu-ray (Filme + TV-Serien)
- ✅ API-Key Eingabefeld in Einstellungen
- ✅ Automatische Metadaten-Erstellung (.nfo + -thumb.jpg)
- ✅ Film/TV-Serien-Auswahl Modals im Web-Interface
- ✅ Type-Selection Modal (Film vs. TV-Serie)
- ✅ TV-Serien Support (TMDB /tv Endpoint, Creator statt Director)
- ✅ Archiv-Ansicht für DVD/Blu-ray erweitert
- ✅ DVD/Blu-ray Placeholder (Disc + Clapperboard)
- ✅ Dokumentation (TMDB-API-Key.md)

## Support

Bei Problemen:
1. TMDB API-Key prüfen (Einstellungen → TMDB API)
2. Logs überprüfen (`/api/logs/current`)
3. TMDB-API-Status: https://status.themoviedb.org/
4. Dokumentation: `/help` → TMDB API-Key Beschaffung
