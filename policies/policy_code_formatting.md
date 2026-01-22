# Code-Formatierungs-Policy

Diese Policy definiert verbindliche Regeln für die Formatierung von Quellcode im Projekt und dient als technische Vorgabe für Entwickler.

## Allgemeine Formatierungsgrundsätze

1. **Einrückung**: 4 Leerzeichen für jede Einrückungsebene. Keine Tabs verwenden.
2. **Zeilenlänge**: Maximale Zeilenlänge von 120 Zeichen.
3. **Zeilenenden**: Unix-Style (LF), keine Windows-Style Zeilenenden (CRLF).
4. **Dateiende**: Jede Datei endet mit einer Leerzeile.

## HTML-Dateien

1. **Dokumentstruktur**: Klare Trennung und einheitliche Struktur:

   ```html
   <!-- Dateipfad und Beschreibung -->
   <!DOCTYPE html>
   <html lang="de">
   <head>
       <!-- Meta-Tags und Stylesheets -->
   </head>
   <body>
       <!-- Header -->
       <header>...</header>
       
       <!-- Hauptinhalt -->
       <main>...</main>
       
       <!-- Footer -->
              <footer>...</footer>
       
       <!-- Skripte -->
       <script src="..."></script>
   </body>
   </html>
   ```

2. **Kommentierung**:
   - Jede HTML-Datei beginnt mit einem Kommentar zur Datei und ihrer Funktion.
   - Hauptabschnitte werden durch Kommentare markiert (z.B. `<!-- header-block //-->`).

3. **Einrückung**:
   - Einrückung von 4 Leerzeichen für jede Verschachtelungsebene.
   - HTML-Elemente mit Block-Charakter beginnen auf einer neuen Zeile.
   - Inhalt von Block-Elementen wird eingerückt.

4. **Attribute**:
   - Attribute werden mit doppelten Anführungszeichen umschlossen.
   - Bei vielen Attributen können diese auf separate Zeilen mit Einrückung gesetzt werden.

5. **Semantische Struktur**:
   - Verwendung semantisch korrekter HTML5-Elemente (header, main, nav, article, section, footer).
   - Keine überflüssigen Elemente oder reinen Layout-Zweck-Elemente (außer für CSS-Styling).

6. **Konsistente Formatierung**:
   - Konsistente Schreibweise für alle HTML-Dateien des Projekts.
   - Leerzeilen zur Trennung logischer Abschnitte.
   - Keine überflüssigen Leerzeilen oder Leerzeichen.

## JavaScript-Dateien (disk2iso Web-Frontend)

**Modulare Struktur:**

```javascript
// ============================================================================
// MODULE: module-name.js
// Beschreibung: Kurzbeschreibung des Moduls
// ============================================================================

// Globale Variablen
let currentState = null;
const API_ENDPOINT = '/api';

// ============================================================================
// API CALLS
// ============================================================================

/**
 * Beschreibung der Funktion
 * @param {string} param - Beschreibung
 * @returns {Promise} Response-Objekt
 */
async function functionName(param) {
    // Implementierung
}

// ============================================================================
// UI HANDLING
// ============================================================================

function updateUI(data) {
    // Implementierung
}
```

1. **Einrückung und Blöcke**:
   - Einrückung von 4 Leerzeichen für jeden Block.
   - Öffnende geschweifte Klammern am Ende der Zeile.
   - Schließende geschweifte Klammern auf einer eigenen Zeile.
   - Strukturierung durch Funktionsblöcke mit Kommentaren.

2. **Variablen und Bezeichner**:
   - camelCase für Variablen und Funktionen.
   - UPPER_CASE für Konstanten.
   - Aussagekräftige Namen, keine Ein-Buchstaben-Variablen außer in Schleifen.

3. **Funktionsdokumentation**:
   - Funktionen werden mit einem Block-Kommentar dokumentiert.
   - Parameter und Rückgabewerte werden beschrieben.
   - JSDoc-Format für API-Funktionen.

4. **Kommentare**:
   - Sinnvolle Kommentare für komplexe Funktionen.
   - Kommentarblöcke zur Trennung von Abschnitten.
   - Separator-Linien für Module (80 Zeichen).

## CSS-Dateien

1. **Formatierung**:
   - Eine CSS-Eigenschaft pro Zeile.
   - Leerzeile zwischen Selektoren.
   - Gruppierung verwandter Selektoren.

2. **Namenskonventionen**:
   - kebab-case für CSS-Klassen und IDs.
   - Modulare Benennung nach BEM-Methodik (Block-Element-Modifier) wird empfohlen.

3. **Hierarchie**:
   - Selektoren nach ihrer Verwendung im HTML strukturieren.
   - Vermeidung tiefer Verschachtelungen.

## Python-Dateien (disk2iso Web-Backend)

**Flask-App Struktur:**

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
################################################################################
# disk2iso Web Interface
# File: www/app.py
# Description: Flask REST API Backend
################################################################################

from flask import Flask, jsonify, request
import logging

# ============================================================================
# CONFIGURATION
# ============================================================================

app = Flask(__name__)
API_VERSION = "1.2.0"

# ============================================================================
# ROUTES
# ============================================================================

@app.route('/api/endpoint', methods=['GET', 'POST'])
def endpoint_handler():
    """
    Beschreibung des Endpoints
    
    Returns:
        JSON response with status and data
    """
    # Implementierung
    return jsonify({"status": "success", "data": result})
```

1. **Namenskonventionen**:
   - snake_case für Funktionen und Variablen
   - PascalCase für Klassen
   - UPPER_CASE für Konstanten

2. **Docstrings**: Google-Style Docstrings für alle Funktionen

3. **API-Responses**: Immer JSON mit `status` und `data`/`error` Feldern

## Implementation und Einhaltung

1. **Code-Reviews**: Bei jedem Code-Review wird auch die Einhaltung dieser Formatierungsregeln geprüft.

2. **disk2iso-spezifisch**:
   - ShellCheck für alle Bash-Module
   - Prüfung der Provider-Registrierung
   - Validierung von JSON-Responses
   - Test der Mehrsprachigkeit

3. **Ausnahmen**: Begründete Ausnahmen müssen dokumentiert werden, sollten aber vermieden werden.

4. **Legacy-Code**: Bestehender Code wird schrittweise auf diese Standards migriert.

**Stand**: 21. Januar 2026 (disk2iso v1.2.0)
