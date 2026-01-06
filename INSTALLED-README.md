# disk2iso - Installierte Version

Diese Installation von disk2iso befindet sich in `/opt/disk2iso`.

## 🚀 Verwendung

### Manuell ausführen
```bash
disk2iso -o /pfad/zum/ausgabe/verzeichnis
```

### Als Service (falls installiert)
```bash
# Status prüfen
systemctl status disk2iso

# Logs ansehen
journalctl -u disk2iso -f

# Service neustarten
sudo systemctl restart disk2iso

# Service stoppen
sudo systemctl stop disk2iso

# Service starten
sudo systemctl start disk2iso
```

## 🔄 Updates durchführen

Um disk2iso zu aktualisieren:

```bash
# 1. Service stoppen (falls aktiv)
sudo systemctl stop disk2iso

# 2. Update installieren
sudo /opt/disk2iso/install.sh

# 3. Service neu starten (falls gewünscht)
sudo systemctl start disk2iso
```

**Hinweis:** Das Update-Skript überschreibt alle Dateien in `/opt/disk2iso` außer Konfigurationen in `lib/config.sh`, die bewahrt werden.

## 🗑️ Deinstallation

Um disk2iso komplett zu entfernen:

```bash
sudo /opt/disk2iso/uninstall.sh
```

Der Deinstallations-Wizard fragt Sie:
- Ob der systemd-Service entfernt werden soll
- Ob das Ausgabeverzeichnis mit allen ISOs gelöscht werden soll

## 📁 Verzeichnisstruktur

```
/opt/disk2iso/
├── disk2iso.sh          # Hauptprogramm
├── install.sh           # Update-/Installations-Skript
├── uninstall.sh         # Deinstallations-Skript
├── lib/                 # Bibliotheken
│   ├── config.sh       # Konfiguration (MQTT, Ausgabeverzeichnis)
│   └── lib-*.sh        # Modul-Bibliotheken
├── doc/                 # Dokumentation
├── lang/                # Sprachdateien (DE/EN)
├── service/             # systemd Service-Definitionen
└── www/                 # Web-Server (zukünftig)
```

## ⚙️ Konfiguration

Die Hauptkonfiguration befindet sich in:
```
/opt/disk2iso/lib/config.sh
```

Wichtige Einstellungen:
- `DEFAULT_OUTPUT_DIR` - Standard-Ausgabeverzeichnis für ISOs
- `MQTT_ENABLED` - MQTT-Integration aktivieren/deaktivieren
- `MQTT_BROKER` - MQTT Broker IP-Adresse
- `LANGUAGE` - Sprache (de/en)

**Nach Konfigurationsänderungen:**
```bash
sudo systemctl restart disk2iso
```

## 📖 Dokumentation

Weitere Dokumentation finden Sie unter:
- `/opt/disk2iso/doc/Handbuch.md` - Vollständige Anleitung
- `/opt/disk2iso/doc/Verwendung.md` - Nutzungsbeispiele
- `/opt/disk2iso/doc/MQTT-HomeAssistant.md` - MQTT Integration
- `/opt/disk2iso/README.md` - Projekt-README

## 🆘 Hilfe

```bash
disk2iso --help
```

## 📝 Version

Sie können die installierte Version überprüfen:
```bash
cat /opt/disk2iso/VERSION
```

Oder mit Details:
```bash
head -n 5 /opt/disk2iso/disk2iso.sh
```

---

**Installiert am:** $(date)  
**Installationsverzeichnis:** /opt/disk2iso  
**Symlink:** /usr/local/bin/disk2iso
