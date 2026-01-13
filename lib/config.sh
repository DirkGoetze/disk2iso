#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Configuration
# Filepath: lib/config.sh
#
# Beschreibung:
#   Zentrale Konfiguration und globale Variablen für disk2iso.
#   Wird von disk2iso.sh beim Start geladen.
#
# Version: 1.2.0
# Datum: 06.01.2026
################################################################################

# ============================================================================
# SPRACH-KONFIGURATION
# ============================================================================

# Sprache für Meldungen (de, en, ...)
# Jedes Modul lädt automatisch lang/lib-[modul].[LANGUAGE]
readonly LANGUAGE="de"

# ============================================================================
# KONFIGURATION
# ============================================================================

# Standard-Ausgabeverzeichnis (wird bei Installation konfiguriert)
# Wird vom Service ausschließlich aus dieser Datei gelesen
DEFAULT_OUTPUT_DIR="/media/iso"

# ============================================================================
# MQTT KONFIGURATION (Home Assistant Integration)
# ============================================================================

# MQTT aktivieren/deaktivieren
MQTT_ENABLED=false

# MQTT Broker-Einstellungen
MQTT_BROKER=""              # z.B. "192.168.20.10" oder "homeassistant.local"
MQTT_PORT=1883              # Standard MQTT Port
MQTT_USER=""                # Optional: MQTT Username
MQTT_PASSWORD=""            # Optional: MQTT Password

# MQTT Topic-Konfiguration
MQTT_TOPIC_PREFIX="homeassistant/sensor/disk2iso"
MQTT_CLIENT_ID="disk2iso-${HOSTNAME}"

# MQTT Publish-Einstellungen
MQTT_QOS=0                  # Quality of Service (0, 1, 2)
MQTT_RETAIN=true            # Retain-Flag (true/false)

# ============================================================================
# TMDB API KONFIGURATION (DVD/Blu-ray Metadaten)
# ============================================================================

# TMDB API-Key von themoviedb.org
# Wird für automatische Film-Metadaten und Cover-Download benötigt
# Siehe doc/TMDB-API-Key.md für Anleitung zur API-Key Registrierung
TMDB_API_KEY=""

# ============================================================================
# AUDIO-CD ENCODING EINSTELLUNGEN
# ============================================================================

# MP3 Qualität (lame -V Parameter)
# 0 = beste Qualität (~245 kbps), 2 = hohe Qualität (~190 kbps), 4 = mittlere Qualität (~165 kbps)
MP3_QUALITY=2

# ============================================================================
# KOPIER-PARAMETER
# ============================================================================

# ddrescue Einstellungen (für beschädigte Discs)
DDRESCUE_RETRIES=1          # Wiederholungen bei Lesefehlern (-r Parameter)

# Hinweis: Blockgröße wird dynamisch ermittelt (Standard: 2048 für optische Medien)
# Hinweis: dd conv=noerror,sync bleibt hardcoded (wichtig für Datenintegrität)

# ============================================================================
# HARDWARE-ERKENNUNG
# ============================================================================

# USB-Laufwerk Erkennung
USB_DRIVE_DETECTION_ATTEMPTS=5  # Anzahl Versuche
USB_DRIVE_DETECTION_DELAY=10    # Sekunden zwischen Versuchen

# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================

OUTPUT_DIR=""      # Ausgabeordner für ISO-Dateien (wird per Parameter oder DEFAULT gesetzt)
disc_label=""      # Normalisierter Label-Name der Disc
iso_filename=""    # Vollständiger Pfad zur ISO-Datei
md5_filename=""    # Vollständiger Pfad zur MD5-Datei
log_filename=""    # Vollständiger Pfad zur Log-Datei
iso_basename=""    # Basis-Dateiname ohne Pfad (z.B. "dvd_video.iso")
temp_pathname=""   # Temp-Verzeichnis für aktuellen Kopiervorgang
disc_type=""       # "data" (vereinfacht)
disc_block_size="" # Block Size des Mediums (wird gecacht)
disc_volume_size="" # Volume Size des Mediums in Blöcken (wird gecacht)
