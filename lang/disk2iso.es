#!/bin/bash
################################################################################
# disk2iso - Archivo de idioma español para disk2iso.sh (script principal)
# Filepath: disk2iso-lib/lang/disk2iso.es
#
# Descripción:
#   Mensajes para el script principal
#
################################################################################

# ============================================================================
# INICIO DEL SISTEMA
# ============================================================================

readonly MSG_ABORT_CRITICAL_DEPENDENCIES="ABORTADO: Faltan dependencias críticas"
readonly MSG_ABORT_SYSTEMINFO_DEPENDENCIES="ABORTADO: Faltan dependencias de System-Info"
readonly MSG_MQTT_SUPPORT_ENABLED="Soporte MQTT activado"
readonly MSG_MQTT_SUPPORT_DISABLED="Soporte MQTT desactivado o no disponible"
readonly MSG_MQTT_MODULE_NOT_INSTALLED="Módulo MQTT no instalado"

# ============================================================================
# DIRECTORIO DE SALIDA
# ============================================================================

readonly MSG_ERROR_OUTPUT_DIR_NOT_EXIST_MAIN="ERROR: El directorio de salida no existe:"
readonly MSG_CONFIG_OUTPUT_DIR="Configure DEFAULT_OUTPUT_DIR en /opt/disk2iso/lib/config.sh"
readonly MSG_ERROR_NO_WRITE_PERMISSION="ERROR: Sin permisos de escritura para:"
readonly MSG_FIX_PERMISSIONS="Ejecute: sudo chmod -R 777"

# ============================================================================
# MÁQUINA DE ESTADOS
# ============================================================================

readonly MSG_STATE_MACHINE_STARTED="Máquina de estados iniciada"
readonly MSG_ERROR_UNKNOWN_STATE="ERROR: Estado desconocido:"

# ============================================================================
# CONTROL DEL SERVICIO
# ============================================================================

readonly MSG_SERVICE_STOPPING="El servicio se está deteniendo"
