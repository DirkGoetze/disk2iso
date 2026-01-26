#!/bin/bash
################################################################################
# disk2iso - Archivo de Idioma Español para lib-config.sh
# Filepath: lang/lib-config.es
#
# Descripción:
#   Textos de mensajes para funciones de configuración y verificación de manifiestos
#
################################################################################

# ============================================================================
# VERIFICACIÓN DE DEPENDENCIAS BASADA EN MANIFIESTOS
# ============================================================================

# Mensajes Generales
readonly MSG_CONFIG_CHECK_DEPENDENCIES="Verificando dependencias para módulo"

# Verificación de Manifiesto
readonly MSG_CONFIG_NO_MANIFEST="No se encontró manifiesto, omitiendo verificación de dependencias"
readonly MSG_CONFIG_UNKNOWN_FILE_TYPE="Tipo de archivo desconocido en manifiesto"

# Verificación de Archivos del Módulo
readonly MSG_CONFIG_MODULE_FILES_MISSING="Faltan archivos del módulo (módulo instalado incompletamente o corrupto?)"
readonly MSG_CONFIG_MODULE_FILES_HINT="Nota: Verifique la instalación del módulo o actualice el manifiesto"
readonly MSG_CONFIG_NO_LANGUAGE_FILES="no se encontraron archivos de idioma"

# Verificación de Carpetas
readonly MSG_CONFIG_ENSURE_SUBFOLDER_UNAVAILABLE="ensure_subfolder() no disponible - omitiendo verificación de carpetas"
readonly MSG_CONFIG_FOLDER_OK="Carpeta OK"
readonly MSG_CONFIG_FOLDER_CREATION_FAILED="Falló la creación de carpeta"
readonly MSG_CONFIG_CRITICAL_FOLDERS_MISSING="Faltan carpetas críticas y no se pudieron crear"
readonly MSG_CONFIG_CHECK_WRITE_PERMISSIONS="Verifique permisos de escritura en OUTPUT_DIR"
readonly MSG_CONFIG_FOLDERS_AVAILABLE="Carpetas del módulo disponibles"
readonly MSG_CONFIG_FOLDERS_COUNT="carpetas verificadas/creadas"

# Verificación de Herramientas Externas
readonly MSG_CONFIG_CRITICAL_TOOLS_MISSING="Faltan herramientas críticas"
readonly MSG_CONFIG_INSTALL_TOOLS="Instalación: sudo apt install"

# Verificación de Herramientas Opcionales
readonly MSG_CONFIG_OPTIONAL_TOOLS_MISSING="Faltan herramientas opcionales (funcionalidad reducida)"
readonly MSG_CONFIG_RECOMMENDED_INSTALL="Recomendado: sudo apt install"

# Éxito
readonly MSG_CONFIG_ALL_DEPENDENCIES_MET="Todas las dependencias del módulo cumplidas"
