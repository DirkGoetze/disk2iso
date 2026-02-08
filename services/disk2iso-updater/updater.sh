#!/bin/bash
# ===========================================================================
# Volatile Data Updater
# ===========================================================================
# Filepath: services/disk2iso-updater/updater.sh
#
# Beschreibung:
#   Aktualisiert flüchtige System-Daten (Uptime, Speicherplatz)
#   Wird von systemd Timer zyklisch (alle 30s) ausgeführt
#
# ---------------------------------------------------------------------------
# Dependencies: libsysteminfo.sh, libfolders.sh, libsettings.sh
# ---------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# Last Change: 2026-02-05
# ===========================================================================

# Ermittle Installationsverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hauptverzeichnis ist zwei Ebenen höher (von services/disk2iso-updater/ nach root)
INSTALL_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Lade erforderliche Libraries
source "${INSTALL_DIR}/lib/liblogging.sh" || exit 1
source "${INSTALL_DIR}/lib/libfolders.sh" || exit 1
source "${INSTALL_DIR}/lib/libsettings.sh" || exit 1
source "${INSTALL_DIR}/lib/libsysteminfo.sh" || exit 1
source "${INSTALL_DIR}/lib/libservice.sh" || exit 1

# ===========================================================================
# Main
# ===========================================================================

# Sammle flüchtige Daten (mit logger für systemd)
{
    # Uptime-Information aktualisieren
    systeminfo_collect_uptime_info || echo "Fehler beim Sammeln von Uptime-Daten" >&2
    
    # Speicherplatz-Information aktualisieren
    systeminfo_collect_storage_info || echo "Fehler beim Sammeln von Storage-Daten" >&2
    
    # Service-Status aktualisieren
    service_collect_status_info || echo "Fehler beim Sammeln von Service-Status" >&2
    
} 2>&1 | logger -t "disk2iso-volatile-updater" -p user.info

exit 0

# TODO...: ggf in Zukunft weitere flüchtige Daten hier sammeln (z.B. laufende 
# .......  Prozesse, Netzwerkstatus)
# Wichtig: Nur Daten, die schnell und ohne großen Overhead gesammelt werden 
# ........ können, sollten hier hinzugefügt werden, da der Updater alle 30s 
# ........ läuft.
# ........ Daten, die aufwendig zu sammeln sind, sollten besser in den 
# ........ jeweiligen Service-Status-Infos gesammelt und aktualisiert werden, 
# ........ um Performance-Probleme zu vermeiden.
# TODO...: Eventuell in Zukunft in libservice.sh hinzufügen