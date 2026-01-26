#!/bin/bash
################################################################################
# disk2iso - Archivo de idioma español para lib-mqtt.sh
# Filepath: lang/lib-mqtt.es
#
# Descripción:
#   Mensajes para las funciones MQTT
#
################################################################################

# ============================================================================
# DEPENDENCIAS
# ============================================================================
# Nota: Mensajes de verificación de herramientas vienen de lib-config.es (MSG_CONFIG_*)
# Solo mensajes específicos del módulo aquí

readonly MSG_MQTT_SUPPORT_AVAILABLE="Soporte MQTT disponible"
readonly MSG_MQTT_NOT_AVAILABLE="Soporte MQTT no disponible"

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

readonly MSG_MQTT_DISABLED="MQTT está desactivado (MQTT_ENABLED=false)"
readonly MSG_MQTT_ERROR_NO_BROKER="ERROR: MQTT_BROKER no configurado"
readonly MSG_MQTT_INITIALIZED="MQTT inicializado:"
readonly MSG_MQTT_ONLINE="MQTT: Estado → en línea"
readonly MSG_MQTT_OFFLINE="MQTT: Estado → fuera de línea"

# ============================================================================
# PUBLICACIÓN
# ============================================================================

readonly MSG_MQTT_PUBLISH_FAILED="Publicación MQTT fallida para el topic"

# ============================================================================
# ACTUALIZACIONES DE ESTADO
# ============================================================================

readonly MSG_MQTT_STATE_IDLE="MQTT: Estado → inactivo (listo)"
readonly MSG_MQTT_STATE_COPYING="MQTT: Estado → copiando"
readonly MSG_MQTT_STATE_WAITING="MQTT: Estado → esperando (retirar medio)"
readonly MSG_MQTT_STATE_COMPLETED="MQTT: Estado → completado"
readonly MSG_MQTT_STATE_ERROR="MQTT: Estado → error"

# ============================================================================
# PROGRESO
# ============================================================================

readonly MSG_MQTT_PROGRESS="MQTT: Progreso →"
readonly MSG_MQTT_COMPLETED="MQTT: Completado →"
readonly MSG_MQTT_ERROR="MQTT: Error →"
