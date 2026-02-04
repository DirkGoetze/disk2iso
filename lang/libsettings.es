#!/bin/bash
################################################################################
# disk2iso - Archivo de idioma español para libsettings.sh
# Filepath: lang/libsettings.es
#
# Descripción:
#   Textos de mensajes para funciones de gestión de configuración (.conf/.ini/.json)
#
################################################################################

# ============================================================================
# VALIDACIÓN DE PARÁMETROS
# ============================================================================
readonly MSG_SETTINGS_MODULE_MISSING="Falta el nombre del módulo"
readonly MSG_SETTINGS_KEY_MISSING="Falta la clave"
readonly MSG_SETTINGS_SECTION_MISSING="Falta la sección"
readonly MSG_SETTINGS_JSON_FILENAME_MISSING="Falta el nombre del archivo JSON"
readonly MSG_SETTINGS_JSON_PATH_MISSING="Falta la ruta JSON"
readonly MSG_SETTINGS_NO_VALUES_PROVIDED="No se proporcionaron valores"
readonly MSG_SETTINGS_NO_KEYVALUE_PAIRS="No se proporcionaron pares clave=valor"

# ============================================================================
# ERRORES DE DEPENDENCIA
# ============================================================================
readonly MSG_SETTINGS_CONFIG_FILE_NOT_FOUND="Archivo de configuración no encontrado"
readonly MSG_SETTINGS_MODULE_LIBFOLDERS_UNAVAILABLE="folders_get_conf_dir() no disponible. ¡Cargue libfolders.sh primero!"
readonly MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE="get_module_ini_path() no disponible. ¡Cargue libfiles.sh primero!"

# ============================================================================
# ERRORES DE ARCHIVO
# ============================================================================
readonly MSG_SETTINGS_PATH_RESOLUTION_FAILED="Resolución de ruta fallida para el módulo"
readonly MSG_SETTINGS_MODULE_INI_NOT_FOUND="INI del módulo no encontrado"
readonly MSG_SETTINGS_JSON_FILE_NOT_FOUND="Archivo JSON no encontrado"

# ============================================================================
# ERRORES DE HERRAMIENTAS
# ============================================================================
readonly MSG_SETTINGS_JQ_NOT_AVAILABLE="jq no disponible"

# ============================================================================
# ADVERTENCIAS
# ============================================================================
readonly MSG_SETTINGS_DEFAULT_SAVE_FAILED="No se pudo guardar el valor predeterminado"
readonly MSG_SETTINGS_INVALID_KEYVALUE_PAIR="Par clave=valor no válido omitido"

# ============================================================================
# END OF LIBSETTINGS.ES
# ============================================================================
