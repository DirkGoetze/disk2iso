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
# Mensajes de depuración
readonly MSG_DEBUG_MQTT_CHECK_START="Comprobando dependencias del módulo MQTT..."
readonly MSG_DEBUG_MQTT_CHECK_COMPLETE="Módulo MQTT inicializado correctamente"
readonly MSG_DEBUG_MQTT_NOT_SUPPORTED="MQTT: Bandera de soporte no establecida (faltan dependencias)"
readonly MSG_DEBUG_MQTT_NOT_INITIALIZED="MQTT: Bandera de inicialización no establecida (configuración no cargada)"
readonly MSG_DEBUG_MQTT_NOT_ACTIVATED="MQTT: Bandera de activación no establecida (MQTT_ENABLED=false)"
readonly MSG_DEBUG_MQTT_READY="MQTT: Módulo listo (Soporte + Inicializado + Activado)"
readonly MSG_DEBUG_MQTT_CONFIG_LOADED="Configuración MQTT cargada"
readonly MSG_MQTT_INI_NOT_FOUND="Archivo INI MQTT no encontrado (usando valores predeterminados)"
readonly MSG_MQTT_CONFIG_LOADED="MQTT: Configuración cargada"
readonly MSG_MQTT_NOT_AVAILABLE="Soporte MQTT no disponible"

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

readonly MSG_MQTT_ERROR_BROKER_UNREACHABLE="ERROR: Broker MQTT no alcanzable:"
readonly MSG_MQTT_INITIALIZED="MQTT inicializado:"
readonly MSG_MQTT_ONLINE="MQTT: Estado → en línea"
readonly MSG_MQTT_OFFLINE="MQTT: Estado → fuera de línea"

# ============================================================================
# PUBLICACIÓN
# ============================================================================

readonly MSG_MQTT_PUBLISH_FAILED="Publicación MQTT fallida para el topic"

# Mensajes de depuración (Patrón Observer)
readonly MSG_DEBUG_MQTT_PATH="Ruta del módulo MQTT:"
readonly MSG_DEBUG_MQTT_ACTIVATED="Activado:"
readonly MSG_DEBUG_MQTT_UNKNOWN_FILE="mqtt_publish_from_api: Archivo desconocido"
readonly MSG_DEBUG_MQTT_STATE_PUBLISHED="MQTT: Estado publicado"
readonly MSG_DEBUG_MQTT_PROGRESS_PUBLISHED="MQTT: Progreso publicado"

# Mensajes de advertencia (Errores de lectura de archivos API)
readonly MSG_WARN_MQTT_STATUS_UNREADABLE="MQTT: status.json no legible, omitiendo actualización de estado"
readonly MSG_WARN_MQTT_ATTRIBUTES_UNREADABLE="MQTT: attributes.json no legible, omitiendo actualización de atributos"
readonly MSG_WARN_MQTT_PROGRESS_UNREADABLE="MQTT: progress.json no legible, omitiendo actualización de progreso"
