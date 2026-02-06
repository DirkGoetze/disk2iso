# Feature Request: Archiv-Widget - Modulare Label-Namen

## 📋 Beschreibung
Das `archiv_2x1_systeminfo` Widget zeigt aktuell nur technische Ordnernamen (`/audio`, `/dvd`, `/bd`, `/data`). Für eine bessere User Experience sollten die Module ihre eigenen Display-Namen definieren können.

## 🎯 Ziel
Anzeige von benutzerfreundlichen Labels statt Ordnernamen:
- `/audio` → "Audio CDs"
- `/dvd` → "DVDs"  
- `/bd` → "Blu-rays"
- `/data` → "Daten-Discs"

## 💡 Vorgeschlagene Lösung

### 1. INI-Dateien erweitern
Jedes Kopiermodul erhält in seiner INI-Datei ein neues Feld:

**Beispiel: `disk2iso-audio/conf/libaudio.ini`**
```ini
[folders]
# Ausgabe-Ordner (unterhalb von OUTPUT_DIR)
output=audio
# Display-Name für UI (NEU)
output_label=Audio CDs
# Temporäre Dateien
temp=.temp/audio
```

**Weitere Module:**
- `libdvd.ini` → `output_label=DVDs`
- `libbluray.ini` → `output_label=Blu-rays`
- Kein Label in data → Fallback auf Ordnernamen

### 2. Bash-Getter-Funktionen
Jedes Modul implementiert eine Getter-Funktion:

```bash
# In libaudio.sh
audio_get_output_label() {
    local ini_file=$(get_module_ini_path "audio")
    get_ini_value "$ini_file" "folders" "output_label"
}
```

### 3. Zentrale Iterator-Funktion
In `libsettings.sh` oder `libfiles.sh`:

```bash
get_all_module_output_labels() {
    # Scannt conf/ nach allen lib*.ini
    # Liest output und output_label aus [folders]
    # Gibt JSON-kompatible Ausgabe zurück
    # Format: {"audio":"Audio CDs","dvd":"DVDs",...}
}
```

### 4. Python-API Integration
**In `app.py` bei `/api/archive`:**

```python
def get_module_labels():
    """Liest Modul-Labels aus Bash"""
    result = subprocess.run(
        ['bash', '-c', 'source lib/libsettings.sh && get_all_module_output_labels'],
        capture_output=True, text=True
    )
    return json.loads(result.stdout) if result.returncode == 0 else {}

@app.route('/api/archive')
def api_archive():
    # ... existing code ...
    archive_labels = get_module_labels()  # NEU
    
    return jsonify({
        'archive_counts': archive_counts,
        'archive_labels': archive_labels,  # NEU
        # ... rest ...
    })
```

### 5. JavaScript-Widget Update
**In `archiv_2x1_systeminfo.js`:**

```javascript
function updateArchivWidget(archiveCounts, archiveLabels) {
    const typeOrder = [
        { key: 'data', folder: '/data' },
        { key: 'audio', folder: '/audio' },
        { key: 'dvd', folder: '/dvd' },
        { key: 'bluray', folder: '/bd' }
    ];
    
    typeOrder.forEach(type => {
        const count = archiveCounts[type.key] || 0;
        if (count > 0) {
            // Nutze Label falls vorhanden, sonst Fallback auf Ordner
            const displayName = archiveLabels?.[type.key] || type.folder;
            
            html += `
                <div class="info-row">
                    <span class="info-label">${displayName}</span>
                    <span class="info-value">${count}</span>
                </div>
            `;
        }
    });
}
```

## ✅ Vorteile
- ✅ Vollständig modular (jedes Modul definiert sein Label)
- ✅ Automatische Erkennung (neue Module = neues Label)
- ✅ Fallback auf Ordnernamen wenn Label fehlt
- ✅ Keine Hardcoding im Core
- ✅ Mehrsprachigkeit später einfach erweiterbar (via Sprachdateien)

## 📦 Betroffene Komponenten
- `lib/libsettings.sh` oder `lib/libfiles.sh` - Iterator-Funktion
- `disk2iso-audio/conf/libaudio.ini` - output_label
- `disk2iso-dvd/conf/libdvd.ini` - output_label  
- `disk2iso-bluray/conf/libbluray.ini` - output_label
- `www/app.py` - API-Erweiterung
- `www/static/js/widgets/archiv_2x1_systeminfo.js` - Label-Rendering

## ⏱️ Aufwand
**Geschätzt: ~4 Stunden**
- Bash-Implementierung: 2-3h
- Python-API: 1h
- JavaScript: 30min

## 🔗 Abhängigkeiten
- [ ] Modularisierung abgeschlossen
- [ ] Bestehende Issues abgearbeitet
- [ ] `libsettings.sh` refactoring

## 📌 Priorität
**Low** - Nice-to-have Feature, keine kritische Funktionalität

## 🏷️ Labels
`enhancement`, `ui`, `widget`, `systeminfo`, `future`

---
**Erstellt am:** 2026-02-04  
**Status:** Backlog
