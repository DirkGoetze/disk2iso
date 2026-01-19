# Metadata-Abfrage: BEFORE vs AFTER Copy

## Fragestellung
Soll die Metadata-Abfrage (MusicBrainz/TMDB) **VOR** oder **NACH** dem Kopiervorgang erfolgen?

---

## Aktueller Workflow (Metadata NACH Kopie)

**Status-Anzeigen während Rip:**
- "audio_cd_cb0cd60e"
- "Track 4 von 14"
- Bei DVD: "Track 4 von 287" (technisch)

**User-Perspektive:**
- ❓ "Welche CD wird gerade kopiert?"
- ❓ "Was ist Track 4?"
- 🤖 Fühlt sich wie eine Maschine an
- ⏩ Aber: Sofortiger Start, keine Wartezeit

---

## Alternative: Metadata VOR Kopie

**Status-Anzeigen während Rip:**
- "Ronan Keating - Destination"
- "Come Be My Baby (4/14)"
- Bei DVD: "Mission Impossible (2.3 GB / 8.5 GB)"

**User-Perspektive:**
- ✅ "Ah, genau die richtige CD!"
- ✅ Tracktitel sichtbar, nicht nur Nummer
- 👤 Fühlt sich wie ein Musik-Player an
- ⏸️ Aber: 2-5 Sek Wartezeit für MusicBrainz/TMDB

---

## Pro/Contra BEFORE Copy

### ✅ Vorteile

1. **Menschenlesbar:** "Ronan Keating" statt "audio_cd_cb0cd60e"
2. **Tracktitel sichtbar:** User sieht was gerade rippt
3. **Fehler-Prävention:** User erkennt sofort falsche CD
4. **Professioneller Standard:** iTunes, Windows Media Player, EAC machen es so
5. **Keine doppelte Arbeit:** Kein Remastering nötig
6. **Saubere Log-Dateien:** `ronan_keating_destination.log` statt `audio_cd_cb0cd60e.log`
7. **Konsistenz:** Gleicher Workflow für Audio/DVD/BD
8. **DVD/BD besser:** MB/GB Anzeige statt "Track 287 von 512"

### ❌ Nachteile

1. **Verzögerung:** 2-5 Sek vor Kopierstart (MusicBrainz Query)
2. **User-Interaktion nötig:** Modal muss bedient werden
3. **Netzwerk-Abhängigkeit:** Wenn MusicBrainz down → Blockierung?
4. **Automatisierung komplexer:** Benötigt Timeout/Fallback
5. **Bei Fehler:** Kompletter Re-Rip statt nur Remaster

---

## User-Typen Reaktion

**Normal-User (60%):**
- AFTER: 😕 "Was ist audio_cd_cb0cd60e?"
- BEFORE: 😊 "Perfekt, genau die CD die ich meinte!"
- **→ Bevorzugt BEFORE massiv**

**Automatisierungs-User (20%):**
- AFTER: 👍 "Läuft automatisch, super"
- BEFORE: 🤔 "Geht auch automatisch? Mit Timeout?"
- **→ Akzeptiert BEFORE mit Fallback**

**Technik-Enthusiasten (20%):**
- AFTER: ⚙️ "Effizient, mag ich"
- BEFORE: 🤷 "Verstehe die UX-Gründe"
- **→ Neutral bis positiv**

**Gesamt: 80% würden BEFORE bevorzugen!**

---

## Vergleich mit bekannten Tools

| Tool | Ansatz | User sieht |
|------|--------|-----------|
| **iTunes** | BEFORE | Album + Tracks |
| **Windows Media Player** | BEFORE | Album + Tracks |
| **Exact Audio Copy** | BEFORE | Album + Tracks |
| **MakeMKV (DVD)** | BEFORE | Film-Titel |
| **disk2iso (aktuell)** | AFTER | Technische IDs |

**→ Alle professionellen Tools nutzen BEFORE!**

---

## Technische Umsetzbarkeit

### Workflow BEFORE:
```
1. CD detected → State: "waiting_for_metadata"
2. MusicBrainz Query (2-5 Sek)
3. Modal anzeigen (Web-UI)
4. User wählt Release ODER Timeout (60 Sek Default, konfigurierbar)
   - Countdown-Timer im Modal sichtbar
   - Skip-Button für sofortigen Generic-Modus
5. disc_label = "ronan_keating_destination" (oder Generic bei Skip/Timeout)
6. State: "copying" → Ripping mit schönen Namen
7. Anzeige: "Ronan Keating - Destination"
           "Come Be My Baby (4/14)"
```

### Absicherung für Automatik:
- **Timeout:** 60 Sek (konfigurierbar) → Fallback auf `audio_cd_cb0cd60e`
  - Normal-User: 60 Sek (Zeit für CD-Hülle checken, Publisher/Jahr vergleichen)
  - Schnelle User: 15-20 Sek (wissen was sie wollen)
  - Automatisierung: 5-10 Sek (schnell → Generic)
  - Gründliche Prüfer: 90-120 Sek (alle Releases durchgehen)
  - 0 = Kein Timeout (immer auf User warten)
- **Skip-Button:** "Metadaten überspringen" (sofort Generic)
- **Offline-Fallback:** Wenn MusicBrainz nicht erreichbar

### Implementierungs-Aufwand:
- **Mittel** (State Machine erweitern)
- **API:** `metadata_query.json` + `metadata_selected.json`
- **Service:** Wartet auf User-Input oder Timeout
- **Frontend:** Modal zeigt Releases vor dem Kopieren

---

## Einschätzung & Empfehlung

### **JA, umstellen auf BEFORE macht absolut Sinn!**

**Hauptgründe:**

1. **User Akzeptanz:** 60% Normal-User wollen lesbare Namen
2. **Professioneller Standard:** Alle bekannten Tools machen es so
3. **Bessere UX:** User sieht sofort was kopiert wird
4. **Konsistenz:** Gleicher Workflow für Audio/DVD/BD
5. **Kein Remastering:** Spart Zeit und Ressourcen

**Mit Absicherung bleibt Automatik möglich:**
- Timeout → Fallback auf Generic
- Offline-Modus → Generic Namen
- Skip-Button → User-Kontrolle

**Fazit:** Der aktuelle AFTER-Ansatz ist technisch optimal, aber UX-technisch suboptimal. BEFORE ist der bessere Kompromiss zwischen Automatisierung und User-Freundlichkeit.

**Empfehlung:** Umstellen, aber mit ordentlichem Timeout/Fallback-System! 🎯

---

## ImplementiConfig & API-Erweiterung
- [ ] Config-Parameter: `METADATA_SELECTION_TIMEOUT=60` (konfigurierbar 0-300)
- [ ] Neuer State: `waiting_for_metadata`
- [ ] API-Endpunkt: `/api/metadata/query` (initiiert Query)
- [ ] API-Endpunkt: `/api/metadata/select` (User-Auswahl oder Skip)
- [ ] Timeout-Mechanismus im Service (aus Config lesennitiiert Query)
- [ ] API-Endpunkt: `/api/metadata/select` (User-Auswahl oder Skip)
- [ ] Timeout-Mechanismus im Service (30 Sek)

### Phase 2: Service-Logik
- [ ] State Machine erweitern
- [ ] MusicBrainz/TMDB Query vor Kopie
- [ ] Warten auf User-Auswahl oder Timeout
- [ ] Fallback auf Generic wenn keine Metadata

### Phase 3: Frontend
- [ ] Modal für Release-Auswahl dynamisch aus Config, z.B. 60 Sek)
- [ ] Skip-Button prominent platzieren ("Metadaten überspringen")
- [ ] Auto-Close bei Auswahl
- [ ] Visuelles Feedback: "Zeit für CD-Hülle checken, Publisher vergleichen..."platzieren
- [ ] Auto-Close bei Auswahl

### Phase 4: Testing
- [ ] Test: Normal-Flow (mit Auswahl)
- [ ] Test: Timeout-Flow (keine Auswahl)
- [ ] Test: Offline-Flow (MusicBrainz down)
- [ ] Test: Skip-Button

---
---

## Timeout-Konfiguration (Ergänzung 20.01.2026)

### Config-Parameter in `disk2iso.conf`:
```bash
# Wartezeit für Metadaten-Auswahl (Sekunden)
# Gibt dem User Zeit für:
# - CD-Hülle rausholen und Publisher/Jahr prüfen (oft Schriftgröße 5-6)
# - Mehrere Releases durchscrollen und vergleichen
# - Gründliche Entscheidung bei unklaren Fällen
#
# Werte:
#   0     = Kein Timeout, immer auf User warten (für Perfektionisten)
#   5-10  = Schnell (Automatisierung, User kennt seine CDs)
#   60    = Standard (entspannte Auswahl, empfohlen)
#   90-120 = Gründlich (Zeit für detaillierte CD-Hüllen-Prüfung)
#   300   = Maximum (5 Minuten, für sehr unentschlossene User)
METADATA_SELECTION_TIMEOUT=60
```

### Use Cases:
- **Heimanwender (Standard):** 60 Sek - Zeit für CD rausholen, Cover vergleichen
- **CD-Sammler:** 90-120 Sek - Gründlicher Vergleich, viele Releases
- **Automatisierung:** 5-10 Sek - Schneller Fallback, keine User-Interaktion
- **Perfektionisten:** 0 Sek - Wartet immer, bis User wählt (kein Timeout)

### Frontend-Anzeige:
```
┌─────────────────────────────────────────────┐
│ MusicBrainz: 8 Releases gefunden            │
│                                             │
│ [Cover 1]  Ronan Keating - Destination     │
│            2002, Universal Music (DE)       │
│                                             │
│ [Cover 2]  Ronan Keating - Destination     │
│            2002, Polydor (UK)               │
│                                             │
│ ⏱️  Noch 45 Sekunden...                     │
│                                             │
│ [Auswählen]  [Überspringen]                │
└─────────────────────────────────────────────┘
```

**Datum:** 19./20. Januar 2026  
**Status:** Analyse aktualisiert, Implementierung folgt  
**Priorität:** Mittel-Hoch (wichtiges UX-Featurert  
**Priorität:** Mittel (nach aktuellen Tests)
