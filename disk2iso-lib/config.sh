#!/bin/bash
################################################################################
# Auto CD/DVD Ripper - Configuration
# Filepath: lib/config.sh
#
# Beschreibung:
#   Zentrale Konfiguration und globale Variablen für den Auto CD/DVD Ripper.
#   Wird von auto-cd-ripper.sh beim Start geladen.
#
################################################################################

# ============================================================================
# KONFIGURATION
# ============================================================================

OUTPUT_DIR="/mnt/hdd/nas/images"      # Standard Ausgabeordner für ISO-Dateien
CD_DEVICE="/dev/sr0"     # Standard CD/DVD-Laufwerk (wird dynamisch ermittelt)

# Audio-CD Konfiguration
AUDIO_OUTPUT_FORMAT="mp3"                               # "mp3", "flac", "wav"
AUDIO_QUALITY="V2"                 # lame -V0 (beste) bis -V9 (kleinste Datei)
AUDIO_USE_MUSICBRAINZ="true"   # MusicBrainz Metadaten-Lookup (erfordert Inet)
AUDIO_USE_CDTEXT="true"                       # CD-TEXT als Fallback verwenden
AUDIO_DOWNLOAD_COVER="true"          # Album-Cover herunterladen und einbetten

# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================

disk_label=""      # Normalisierter Label-Name der Disc
iso_filename=""    # Vollständiger Pfad zur ISO-Datei
md5_filename=""    # Vollständiger Pfad zur MD5-Datei
log_filename=""    # Vollständiger Pfad zur Log-Datei
iso_basename=""    # Basis-Dateiname ohne Pfad (z.B. "dvd_video.iso")
temp_pathname=""   # Temp-Verzeichnis für aktuellen Kopiervorgang
disc_type=""       # "audio-cd", "video-dvd", "data-dvd", "video-bluray", "data-bluray", "unknown"
disc_block_size="" # Block Size des Mediums (wird gecacht)
disc_volume_size="" # Volume Size des Mediums in Blöcken (wird gecacht)
