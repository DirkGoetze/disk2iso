# Migration Status: Sprachkonstanten-Verwendung

**Stand:** 30.12.2025  
**Status:** TEILWEISE IMPLEMENTIERT

---

## ✅ Abgeschlossen

### lib-common.de
- ✅ Erweitert mit allen benötigten Konstanten (Speicherplatz, Methoden, ISO-Volume, Fortschritt)
- ✅ `MSG_OPTIONAL_TOOLS_INFO` - VERWENDET
- ✅ `MSG_INSTALL_GENISOIMAGE_GDDRESCUE` - VERWENDET
- ✅ `MSG_DATA_DISC_SUCCESS_DDRESCUE` - VERWENDET (2x)
- ✅ `MSG_ERROR_DDRESCUE_FAILED` - VERWENDET (2x)

### lib-cd.de
- ✅ Erweitert mit allen benötigten Konstanten (Metadaten, Ripping, NFO)
- ✅ `MSG_AUDIO_SUPPORT_NOT_AVAILABLE` - VERWENDET
- ✅ `MSG_INSTALL_AUDIO_TOOLS` - VERWENDET
- ✅ `MSG_AUDIO_OPTIONAL_LIMITED` - VERWENDET
- ✅ `MSG_INSTALL_MUSICBRAINZ_TOOLS` - VERWENDET
- ✅ `MSG_AUDIO_SUPPORT_AVAILABLE` - VERWENDET

### lib-dvd.de
- ✅ Erweitert mit allen benötigten Konstanten

### lib-bluray.de
- ✅ Erweitert mit allen benötigten Konstanten

---

## ⏳ Verbleibende Ersetzungen

### lib-common.sh (~10 Stellen)
```bash
# Zeile 118: "ISO-Volume erkannt: ..."
# Zeile 176: "ISO-Volume erkannt: ..."  
# Zeile 199: "Kopiere komplette Disc (kein isoinfo verfügbar)"
# Zeile 234: "Fortschritt: ..."
```

### lib-cd.sh (~50 Stellen)
```bash
# Zeile 90: "Ermittle Audio-CD Metadaten..."
# Zeile 94: "WARNUNG: cd-discid nicht installiert..."
# Zeile 99: "WARNUNG: curl/jq nicht installiert..."
# Zeile 108: "FEHLER: Konnte Disc-ID nicht ermitteln"
# Zeile 117: "Disc-ID: ..."
# Zeile 125: "WARNUNG: Konnte Leadout nicht ermitteln"
# Zeile 141: "Frage MusicBrainz-Datenbank ab..."
# Zeile 145: "WARNUNG: MusicBrainz-Abfrage fehlgeschlagen..."
# Zeile 154: "WARNUNG: Keine MusicBrainz-Einträge gefunden..."
# Zeile 169-171: "Album:", "Künstler:", "Jahr:"
# Zeile 177: "MusicBrainz: ... Track-Titel gefunden"
# Zeile 184: "Cover-Art verfügbar"
# Zeile 189: "WARNUNG: Unvollständige Metadaten..."
# Zeile 215: "WARNUNG: Keine Release-ID..."
# Zeile 223: "Lade Album-Cover herunter..."
# Zeile 229: "Cover heruntergeladen: ..."
# Zeile 235: "WARNUNG: Cover-Download fehlgeschlagen"
# Zeile 273: "INFO: Keine MusicBrainz-Daten - album.nfo übersprungen"
# Zeile 277: "Erstelle album.nfo..."
# Zeile 347: "album.nfo erstellt"
# Zeile 358: "Starte Audio-CD Ripping..."
# Zeile 362: "FEHLER: cdparanoia nicht installiert"
# Zeile 367: "FEHLER: lame nicht installiert"
# Zeile 372: "FEHLER: genisoimage nicht installiert"
# Zeile 377: "Fahre ohne Metadaten fort..."
# Zeile 384: "INFO: eyeD3 nicht installiert..."
# Zeile 418: "Album-Verzeichnis: ..."
# Zeile 426: "FEHLER: Keine Tracks gefunden"
# Zeile 431: "Gefundene Tracks: ..."
# Zeile 434: "Starte Ripping mit cdparanoia..."
# Zeile 440: "Rippe Track ... von ..."
# Zeile 443: "FEHLER: Track ... konnte nicht gerippt werden"
# Zeile 460: "Kodiere Track ... zu MP3: ..."
# Zeile 464: "Kodiere Track ... zu MP3..."
# Zeile 488: "FEHLER: MP3-Encoding ... fehlgeschlagen"
# Zeile 506: "Cover als folder.jpg gespeichert"
# Zeile 512: "Ripping abgeschlossen - erstelle ISO..."
# Zeile 525: "FEHLER: Nicht genügend Speicherplatz..."
# Zeile 539-540: "Erstelle ISO:", "Volume-ID:"
# Zeile 548: "FEHLER: ISO-Erstellung fehlgeschlagen"
# Zeile 558: "FEHLER: ISO-Datei wurde nicht erstellt"
# Zeile 563: "ISO erstellt: ... MB"
# Zeile 566: "Erstelle MD5-Checksumme..."
# Zeile 568: "WARNUNG: MD5-Checksumme konnte nicht erstellt werden"
# Zeile 571: "Audio-CD erfolgreich gerippt..."
```

### lib-dvd.sh (~25 Stellen)
```bash
# Zeile 67: "Video-DVD/BD Support verfügbar mit: ..."
# Zeile 70: "Erweiterte Methoden verfügbar..."
# Zeile 71: "Installation: apt-get install..."
# Zeile 76: "FEHLER: Keine Video-DVD/BD Methode verfügbar"
# Zeile 89: "Methode: dvdbackup (entschlüsselt)"
# Zeile 102: "DVD-Größe: ... MB"
# Zeile 116: "Extrahiere DVD-Struktur..."
# Zeile 158: "Fortschritt: ... MB von ... MB (...)%"
# Zeile 160: "Fortschritt: ... MB kopiert"
# Zeile 173: "FEHLER: dvdbackup fehlgeschlagen..."
# Zeile 178: "✓ DVD-Struktur extrahiert (100%)"
# Zeile 185: "FEHLER: Kein VIDEO_TS Ordner gefunden"
# Zeile 191: "Erstelle entschlüsselte ISO aus VIDEO_TS..."
# Zeile 193: "✓ Entschlüsselte Video-DVD ISO erfolgreich erstellt"
# Zeile 197: "FEHLER: genisoimage fehlgeschlagen"
# Zeile 211: "Methode: ddrescue (verschlüsselt, robust)"
# Zeile 224: "ISO-Volume erkannt: ..."
# Zeile 242: "✓ Video-DVD mit ddrescue erfolgreich kopiert"
# Zeile 246: "FEHLER: ddrescue fehlgeschlagen"
# Zeile 253: "✓ Video-DVD mit ddrescue erfolgreich kopiert"
# Zeile 257: "FEHLER: ddrescue fehlgeschlagen"
```

### lib-bluray.sh (~30 Stellen)
```bash
# Zeile 57: "WARNUNG: genisoimage fehlt..."
# Zeile 72: "Blu-ray Support verfügbar mit: ..."
# Zeile 75-78: "Erweiterte Methoden...", "MakeMKV Download:", "ddrescue:", "genisoimage:"
# Zeile 83: "FEHLER: Keine Blu-ray Methode verfügbar"
# Zeile 96: "Methode: MakeMKV (entschlüsselt)"
# Zeile 103: "Analysiere Blu-ray mit MakeMKV..."
# Zeile 110: "FEHLER: MakeMKV kann Disc nicht erkennen"
# Zeile 120: "FEHLER: Keine Titel auf Blu-ray gefunden"
# Zeile 125: "Gefundene Titel auf Blu-ray: ..."
# Zeile 131: "Disc-Name: ..."
# Zeile 141: "Blu-ray-Größe: ... MB"
# Zeile 154-155: "Starte MakeMKV Backup...", "Dies kann ... dauern..."
# Zeile 199: "MakeMKV Fortschritt: ... MB von ... MB"
# Zeile 201: "MakeMKV Fortschritt: ... MB kopiert"
# Zeile 214: "FEHLER: MakeMKV Backup fehlgeschlagen..."
# Zeile 219: "✓ MakeMKV Backup erfolgreich abgeschlossen (100%)"
# Zeile 226: "FEHLER: Kein BDMV Ordner im Backup gefunden"
# Zeile 231: "BDMV-Struktur gefunden: ..."
# Zeile 234: "Erstelle entschlüsselte ISO aus BDMV-Struktur..."
# Zeile 238: "✓ Entschlüsselte Blu-ray ISO erfolgreich erstellt"
# Zeile 242: "FEHLER: ISO-Erstellung mit genisoimage fehlgeschlagen"
# Zeile 256: "Methode: ddrescue (verschlüsselt, robust)"
# Zeile 269: "ISO-Volume erkannt: ..."
# Zeile 284: "Starte ddrescue (Blu-ray bleibt verschlüsselt)..."
# Zeile 289: "✓ Blu-ray mit ddrescue erfolgreich kopiert"
# Zeile 293: "FEHLER: ddrescue fehlgeschlagen"
# Zeile 300: "✓ Blu-ray mit ddrescue erfolgreich kopiert"
# Zeile 304: "FEHLER: ddrescue fehlgeschlagen"
```

### lib-logging.sh (~3 Stellen)
```bash
# Zeile 51: "Sprachdatei geladen: ..."
# Zeile 59: "Fallback: Sprachdatei geladen: ..."
# Zeile 64: "WARNUNG: Keine Sprachdatei gefunden..."
```

### lib-folders.sh (~6 Stellen)
```bash
# Zeile 51: "Temp-Verzeichnis erstellt: ..."
# Zeile 59: "Temp-Verzeichnis bereinigt: ..."
# Zeile 97: "Log-Verzeichnis sichergestellt: ..."
# Zeile 109: "Ausgabe-Verzeichnis sichergestellt: ..."
# Zeile 158: "Album-Verzeichnis erstellt: ..."
# Zeile 173: "FEHLER: Konnte Backup-Verzeichnis nicht erstellen: ..."
# Zeile 176: "Backup-Verzeichnis erstellt: ..."
```

---

## 🎯 Empfehlung

**Phase 1 (Kritisch) - TEILWEISE ERLEDIGT ✅:**
- Dependency-Check Meldungen → 50% ersetzt
- Erfolgs-/Fehlermeldungen → 20% ersetzt

**Phase 2 (Mittel) - TODO:**
- Fortschritts-Meldungen (~10 Stellen)
- Methoden-Auswahl (~5 Stellen)
- ISO-Volume Erkennungen (~4 Stellen)

**Phase 3 (Niedrig) - TODO:**
- Debug/Info-Meldungen in lib-logging.sh
- Verzeichnis-Meldungen in lib-folders.sh

---

## 💡 Automatisierungs-Script

Wegen der vielen Ersetzungen (~100 verbleibend) empfehle ich ein Migration-Script zu erstellen:

```bash
#!/bin/bash
# migrate_to_language_constants.sh

# Ersetze alle hardcodierten Strings durch MSG_ Konstanten
# in allen lib-*.sh Dateien

# Liste der Ersetzungen als Array...
```

Alternativ: Schrittweise manuelle Migration Modul für Modul mit Tests dazwischen.

---

## 📈 Fortschritt

- **Gesamt:** ~120 hardcodierte Meldungen
- **Ersetzt:** ~10 (8%)
- **Verbleibend:** ~110 (92%)
- **Erweiterte Konstanten:** 40 → 120 (300% Zuwachs)

**Zeitaufwand geschätzt:** 3-4 Stunden für komplette Migration

