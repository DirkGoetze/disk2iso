# Frontend-Modularisierung - Dynamisches JS-Loading

## Problem
Aktuell werden alle JavaScript-Dateien pauschal in Templates geladen, unabhängig davon ob das entsprechende Modul aktiviert ist. Bei deaktivierten Modulen werden unnötige Ressourcen geladen und potenziell Fehler durch fehlende Backend-APIs verursacht.

## Lösung: Zentraler Module-Loader

### Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                         Frontend                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ base.html                                             │  │
│  │  └─ module-loader.js (Zentrale Koordination)         │  │
│  │      ↓                                                │  │
│  │  1. GET /api/modules (Welche Module aktiv?)          │  │
│  │  2. Dynamisches Laden nur aktiver Module             │  │
│  │      ├─ metadata → musicbrainz.js, tmdb.js           │  │
│  │      ├─ cd → (keine JS-Dateien)                      │  │
│  │      ├─ dvd → (keine JS-Dateien)                     │  │
│  │      └─ mqtt → (keine JS-Dateien)                    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                         Backend                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ app.py                                                │  │
│  │  └─ /api/modules                                      │  │
│  │      ↓                                                │  │
│  │  get_config() liest disk2iso.conf                    │  │
│  │      ↓                                                │  │
│  │  {"enabled_modules": {                                │  │
│  │      "metadata": true,                                │  │
│  │      "cd": true,                                      │  │
│  │      "dvd": false,  ← Deaktiviert                     │  │
│  │      "bluray": true,                                  │  │
│  │      "mqtt": false                                    │  │
│  │  }}                                                   │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Komponenten

#### 1. Backend: `/api/modules` Endpoint

**Datei:** `www/app.py`

```python
@app.route('/api/modules')
def api_modules():
    """API-Endpoint für Modul-Status"""
    config = get_config()
    
    enabled_modules = {
        'metadata': config.get('metadata_enabled', True),
        'cd': config.get('cd_enabled', True),
        'dvd': config.get('dvd_enabled', True),
        'bluray': config.get('bluray_enabled', True),
        'mqtt': config.get('mqtt_enabled', False)
    }
    
    return jsonify({'enabled_modules': enabled_modules})
```

**Konfiguration lesen:**

```python
def get_config():
    config = {
        "metadata_enabled": True,  # Defaults
        "cd_enabled": True,
        "dvd_enabled": True,
        "bluray_enabled": True,
        # ...
    }
    
    # Parse disk2iso.conf
    if line.startswith('METADATA_ENABLED='):
        config['metadata_enabled'] = 'true' in line.lower()
    elif line.startswith('CD_ENABLED='):
        config['cd_enabled'] = 'true' in line.lower()
    # ...
```

#### 2. Frontend: Module-Loader Script

**Datei:** `www/static/js/module-loader.js`

**Funktionsweise:**

1. **Modul-Definitionen:** Mapping von Modul-Namen zu JS-Dateien
   ```javascript
   const MODULE_DEFINITIONS = {
       'metadata': {
           files: ['musicbrainz.js', 'tmdb.js'],
           init: function() { /* Init-Code */ }
       },
       'cd': { files: [] },  // Kein JS
       'dvd': { files: [] },
       // ...
   };
   ```

2. **Dynamisches Script-Loading:**
   ```javascript
   function loadScript(src) {
       return new Promise((resolve, reject) => {
           const script = document.createElement('script');
           script.src = `/static/js/${src}?v=${Date.now()}`;
           script.onload = () => resolve();
           script.onerror = () => reject();
           document.body.appendChild(script);
       });
   }
   ```

3. **Modul-Initialisierung:**
   ```javascript
   async function initializeModules() {
       // 1. Frage Backend
       const response = await fetch('/api/modules');
       const data = await response.json();
       
       // 2. Lade nur aktivierte Module
       for (const [name, enabled] of Object.entries(data.enabled_modules)) {
           if (enabled && MODULE_DEFINITIONS[name]) {
               await loadModule(name, MODULE_DEFINITIONS[name]);
           }
       }
       
       // 3. Event für andere Scripts
       document.dispatchEvent(new CustomEvent('modulesLoaded'));
   }
   ```

#### 3. Template-Integration

**Datei:** `www/templates/base.html`

```html
<head>
    <!-- Zentrale Lade-Logik -->
    <script src="/static/js/module-loader.js?v={{ version }}"></script>
</head>
```

**Datei:** `www/templates/archive.html` (Beispiel)

```html
{% block scripts %}
    <!-- ❌ ALT: Pauschales Laden -->
    <!-- <script src="tmdb.js"></script> -->
    <!-- <script src="musicbrainz.js"></script> -->
    
    <!-- ✅ NEU: Nur seitenspezifisches Script -->
    <script src="archive.js"></script>
    
    <!-- Modul-Scripts werden automatisch geladen falls aktiv -->
{% endblock %}
```

### Ablauf

1. **Seitenaufruf:** User öffnet Archive-Seite
2. **base.html lädt:** `module-loader.js` wird sofort geladen
3. **module-loader.js startet:** 
   - `DOMContentLoaded` Event triggert `initializeModules()`
4. **Backend-Abfrage:** `GET /api/modules`
   ```json
   {
       "enabled_modules": {
           "metadata": true,
           "cd": true,
           "dvd": false,
           "bluray": true,
           "mqtt": false
       }
   }
   ```
5. **Dynamisches Laden:**
   - `metadata=true` → Lädt `musicbrainz.js`, `tmdb.js`
   - `cd=true` → Keine JS-Dateien
   - `dvd=false` → **Wird übersprungen!**
   - `mqtt=false` → Wird übersprungen
6. **Init-Callbacks:** 
   - `initMusicBrainzModal()` wird aufgerufen
   - `initTmdbModal()` wird aufgerufen
7. **Custom Event:** `modulesLoaded` Event für seitenspezifische Scripts
8. **Archive.js kann prüfen:**
   ```javascript
   document.addEventListener('modulesLoaded', (e) => {
       if (window.isModuleLoaded('metadata')) {
           // TMDB/MusicBrainz Features aktivieren
       } else {
           // Nur Download-Buttons anzeigen
       }
   });
   ```

### Vorteile

1. **Keine unnötigen Downloads:** Deaktivierte Module laden kein JS
2. **Keine Runtime-Fehler:** Fehlende APIs werden nicht aufgerufen
3. **Zentrale Verwaltung:** Eine Datei steuert alles
4. **Cache-freundlich:** Cache-Busting via `?v=timestamp`
5. **Erweiterbar:** Neue Module durch Erweiterung von `MODULE_DEFINITIONS`
6. **Testbar:** `window.isModuleLoaded('name')` für Feature-Detection

### Erweiterung für neue Module

**1. Backend (disk2iso.conf):**
```bash
# Neues Modul aktivieren
NEWMODULE_ENABLED=true
```

**2. Backend (app.py → get_config):**
```python
elif line.startswith('NEWMODULE_ENABLED='):
    config['newmodule_enabled'] = 'true' in line.lower()
```

**3. Backend (app.py → api_modules):**
```python
enabled_modules = {
    # ...
    'newmodule': config.get('newmodule_enabled', True),
}
```

**4. Frontend (module-loader.js):**
```javascript
const MODULE_DEFINITIONS = {
    // ...
    'newmodule': {
        files: ['newmodule-ui.js', 'newmodule-api.js'],
        init: function() {
            if (typeof initNewModule === 'function') {
                initNewModule();
            }
        }
    }
};
```

**5. JS-Dateien erstellen:**
```javascript
// www/static/js/newmodule-ui.js
function initNewModule() {
    console.log('NewModule UI initialisiert');
}
```

### Konsistenz mit Plugin-Architektur

Diese Lösung folgt dem Plugin-Konzept aus `todo/Metadata-PlugIn_Konzept.md`:

- **Modul = Plugin:** Jedes Modul kann aktiviert/deaktiviert werden
- **Config-gesteuert:** `*_ENABLED` Variablen steuern alles
- **Unabhängig auslieferbar:** JS-Dateien können separat deployed werden
- **Keine Abhängigkeiten:** Module kennen sich nicht untereinander
- **Zentrale Koordination:** `module-loader.js` ist der Orchestrator

### Migration bestehender Seiten

**Schritt 1:** Identifiziere modul-spezifische Scripts
```bash
# Suche in Templates
grep -r "tmdb\|musicbrainz" www/templates/
```

**Schritt 2:** Entferne aus Templates
```html
<!-- ❌ Entfernen -->
<script src="tmdb.js"></script>
<script src="musicbrainz.js"></script>
```

**Schritt 3:** Ergänze `MODULE_DEFINITIONS`
```javascript
'metadata': {
    files: ['musicbrainz.js', 'tmdb.js'],
    init: function() { /* ... */ }
}
```

**Schritt 4:** Test
```javascript
// In Browser-Konsole
console.log(window.isModuleLoaded('metadata'));  // true/false
```

### Debugging

**Console-Output aktivieren:**
```javascript
// module-loader.js loggt bereits:
[ModuleLoader] Aktivierte Module: {metadata: true, cd: true, ...}
[ModuleLoader] Geladen: musicbrainz.js
[ModuleLoader] Geladen: tmdb.js
[ModuleLoader] Modul geladen: metadata
[ModuleLoader] Alle Module geladen
```

**Prüfe Modul-Status:**
```javascript
// In Browser-Konsole
window.isModuleLoaded('metadata')  // → true
window.isModuleLoaded('dvd')       // → false (wenn deaktiviert)
```

**Backend-Response prüfen:**
```bash
curl http://localhost:5000/api/modules | jq
```

### Siehe auch

- `todo/Metadata-PlugIn_Konzept.md` - Gesamte Plugin-Architektur
- `www/app.py` - Backend-Implementierung
- `www/static/js/module-loader.js` - Frontend-Implementierung
- `www/templates/base.html` - Template-Integration
