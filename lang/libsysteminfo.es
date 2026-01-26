#!/bin/bash
################################################################################
# disk2iso - Archivo de idioma español para lib-systeminfo.sh
# Filepath: lang/lib-systeminfo.es
#
# Versión: 1.2.0
# Fecha: 11.01.2026
################################################################################

# Detección de contenedor
MSG_CONTAINER_DETECTED="✓ Entorno de contenedor detectado:"
MSG_NATIVE_ENVIRONMENT_DETECTED="✓ Entorno de hardware nativo detectado"

# Espacio en disco
MSG_DISK_SPACE_INFO="Espacio en disco:"
MSG_DISK_SPACE_MB_AVAILABLE="MB disponibles,"
MSG_DISK_SPACE_MB_REQUIRED="MB requeridos"
MSG_DISK_SPACE_MB_AVAILABLE_SHORT="MB disponibles"
MSG_WARNING_DISK_SPACE_CHECK_FAILED="⚠ Comprobación de espacio en disco falló (continuando)"
MSG_ERROR_INSUFFICIENT_DISK_SPACE="✗ ¡Espacio en disco insuficiente! Requerido:"

# Cambio de medio
MSG_CONTAINER_MANUAL_EJECT="⚠ Entorno de contenedor: Expulse manualmente el medio e inserte uno nuevo"
MSG_WAITING_FOR_MEDIUM_CHANGE="Esperando cambio de medio..."
MSG_WARNING_NO_MEDIUM_IDENTIFIER="⚠ No se pudo determinar el identificador del medio (esperando cualquier medio)"
MSG_NEW_MEDIUM_DETECTED="✓ Nuevo medio detectado"
MSG_STILL_WAITING="Aún esperando:"
MSG_SECONDS_OF="segundos de"
MSG_SECONDS="segundos"
MSG_TIMEOUT_WAITING_FOR_MEDIUM="✗ Tiempo de espera agotado para el cambio de medio"

# Errores de dependencias del sistema
MSG_ERROR_SYSTEM_TOOLS_MISSING="ERROR: Faltan herramientas del sistema:"
MSG_INSTALLATION_SYSTEM_TOOLS="Instalación: apt-get install lsblk findmnt"
