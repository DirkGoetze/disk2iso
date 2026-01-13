# Refactoring: TMDB Search → Bash (Phase 1)

## Ziel
Verschiebe TMDB Search Business-Logik von Python nach Bash für saubere Architektur-Trennung.

## Status
🔄 In Arbeit (gestartet: 13. Januar 2026)

## Motivation
- **Code-Duplikation eliminieren**: TMDB Search existiert 2x (Python + Bash)
- **Konsistente Architektur**: Alle API-Calls in Bash, Python nur UI
- **Wartbarkeit**: Ein Error-Handling Modell, einheitliches Logging

## Phase 1: TMDB Migration

### Aufgaben
- [x] Analyse und Plan erstellt
- [ ] Neue Funktion `search_tmdb_json()` in lib-dvd-metadata.sh
- [ ] Python Endpoint `/api/metadata/tmdb/search` umbauen
- [ ] Testing: Normale Suche (Movie + TV)
- [ ] Testing: Keine Treffer
- [ ] Testing: Sonderzeichen im Input
- [ ] Testing: API-Fehler/Timeout
- [ ] Deployment und Verifikation

### Technische Details

#### lib-dvd-metadata.sh (NEU):
```bash
search_tmdb_json() {
    local title="$1"
    local media_type="$2"
    
    # API-Call mit curl
    # JSON-Formatierung mit jq
    # Return: {"success": true/false, "results": [...]}
}
```

#### app.py (ANGEPASST):
```python
@app.route('/api/metadata/tmdb/search', methods=['POST'])
def api_tmdb_search():
    # subprocess.run() mit Argument-Array (für Escaping)
    # Parse JSON-Output von Bash
    # Return als Flask Response
```

### Kritische Punkte
1. **String-Escaping**: Argument-Array verwenden, NICHT String-Interpolation
2. **Error-Handling**: Bash gibt IMMER valides JSON zurück
3. **Testing**: Besonders Sonderzeichen testen

### Aufwandsschätzung
- Implementierung: 1h
- Testing: 1h
- **Gesamt: 2h**

### Risiko
**Niedrig** - Funktionen existieren bereits, nur Output-Format ändern

---

## Phase 2: MusicBrainz Migration (Optional, später)

### Aufgaben (noch nicht begonnen)
- [ ] Neue Funktion `search_musicbrainz_json()` in lib-cd-metadata.sh
- [ ] .mbquery Logik in Bash
- [ ] Python Endpoint `/api/metadata/musicbrainz/search` umbauen
- [ ] Testing
- [ ] Deployment

### Aufwandsschätzung
- **Gesamt: 7h** (komplexer wegen Duration-Berechnung, Label-Extraktion)

---

## Vorteile nach Abschluss

✅ **Code-Duplikation eliminiert** (TMDB nur noch 1x)  
✅ **Konsistente Architektur** (alle API-Calls in Bash)  
✅ **Einfacheres Testing** (Bash-Funktionen standalone testbar)  
✅ **Weniger Dependencies** (Python braucht kein `requests` mehr)  
✅ **Einheitliches Logging** (alle API-Calls mit gleicher Strategie)

---

## Notizen
- Existierende Bash-Funktionen: `search_tmdb_tv()`, `search_tmdb_movie()`, `get_tmdb_movie_details()`
- Diese geben Log-Messages zurück → Neue Wrapper-Funktion gibt JSON zurück
- Python Flask nur noch "Pass-Through" Layer
