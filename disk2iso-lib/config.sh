#!/bin/bash
################################################################################
# disk2iso v1.0.0 - Configuration
# Filepath: disk2iso-lib/config.sh
#
# Beschreibung:
#   Zentrale Konfiguration und globale Variablen für disk2iso.
#   Wird von disk2iso.sh beim Start geladen.
#
# Version: 1.0.0
# Datum: 01.01.2026
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
# Kann per -o Parameter überschrieben werden
DEFAULT_OUTPUT_DIR="/srv/iso"

# Proxmox Host für eject in LXC (optional, nur für LXC-Umgebungen)
# Beispiel: PROXMOX_HOST="root@192.168.1.100"
# Leer lassen für native Hardware
PROXMOX_HOST=""

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
