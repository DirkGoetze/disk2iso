# Installation: Video-DVD Unterstützung

## Option 1: Entschlüsselte ISOs (empfohlen, contrib Repository)

Erstellt vollständig entschlüsselte ISOs ohne Kopierschutz.

### libdvdcss2 über libdvd-pkg (empfohlen)

Das offizielle Debian-Paket aus dem contrib-Repository:

```bash
# Aktiviere contrib Repository (einmalig)
su -c "sed -i 's/^\(deb.*debian.*main\)\s*$/\1 contrib/' /etc/apt/sources.list"

# Installiere Pakete
su -c 'apt-get update && apt-get install -y genisoimage dvdbackup libdvd-pkg'

# Kompiliere libdvdcss2 automatisch
su -c 'dpkg-reconfigure libdvd-pkg'
```

**Vorteile:**
- ✓ Entschlüsselte ISOs (direkt verarbeitbar)
- ✓ Schnell: ~10-15 Minuten für 4,7 GB DVD
- ✓ Offizielles Debian contrib-Paket
- ✓ Überspringt Kopierschutz-Bereiche

**Nachteile:**
- ✗ contrib Repository erforderlich (aber offiziell)

---

## Option 2: Verschlüsselte ISOs mit ddrescue (nur Debian Standard-Repos)

Erstellt verschlüsselte aber vollständige ISOs.

### Pakete installieren

```bash
su -c 'apt-get update && apt-get install -y gddrescue genisoimage'
```

**Vorteile:**
- ✓ Nur Standard-Repos
- ✓ Deutlich schneller als dd: ~15-30 Minuten
- ✓ Intelligente Fehlerbehandlung

**Nachteile:**
- ✗ ISOs bleiben verschlüsselt (Weiterverarbeitung benötigt libdvdcss)

---

## Option 3: Fallback ohne zusätzliche Installation

Das Script nutzt automatisch `dd` als Fallback.

**Nachteile:**
- ✗ Sehr langsam bei kopiergeschützten DVDs (Stunden!)
- ✗ ISOs bleiben verschlüsselt

---

## Automatische Methoden-Wahl im Script

Das Script wählt automatisch die beste verfügbare Methode:

1. **dvdbackup + genisoimage** (schnell, entschlüsselt) ← wenn installiert
2. **ddrescue** (schnell, verschlüsselt) ← wenn installiert
3. **dd** (langsam, verschlüsselt) ← immer verfügbar

## Status prüfen

```bash
# Prüfe verfügbare Methoden
command -v dvdbackup && echo "✓ Option 1: dvdbackup (entschlüsselt)"
command -v ddrescue && echo "✓ Option 2: ddrescue (verschlüsselt, schnell)"
echo "✓ Option 3: dd (verschlüsselt, langsam) - immer verfügbar"
```
