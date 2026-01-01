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

# OUTPUT_DIR wird als Parameter beim Start übergeben (-o / --output)
# Keine Standard-Konfiguration mehr

# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================

OUTPUT_DIR=""      # Ausgabeordner für ISO-Dateien (wird per Parameter gesetzt)
disc_label=""      # Normalisierter Label-Name der Disc
iso_filename=""    # Vollständiger Pfad zur ISO-Datei
md5_filename=""    # Vollständiger Pfad zur MD5-Datei
log_filename=""    # Vollständiger Pfad zur Log-Datei
iso_basename=""    # Basis-Dateiname ohne Pfad (z.B. "dvd_video.iso")
temp_pathname=""   # Temp-Verzeichnis für aktuellen Kopiervorgang
disc_type=""       # "data" (vereinfacht)
disc_block_size="" # Block Size des Mediums (wird gecacht)
disc_volume_size="" # Volume Size des Mediums in Blöcken (wird gecacht)
