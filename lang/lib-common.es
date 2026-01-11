#!/bin/bash
################################################################################
# disk2iso - Archivo de idioma español para lib-common.sh
# Filepath: lang/lib-common.es
#
# Descripción:
#   Mensajes para funciones básicas (copia de discos de datos)
#
################################################################################

# ============================================================================
# SISTEMA
# ============================================================================

readonly MSG_CORE_MODULES_LOADED="Funciones básicas cargadas"
readonly MSG_AUDIO_CD_SUPPORT_ENABLED="✓ Soporte Audio-CD activado"
readonly MSG_AUDIO_CD_SUPPORT_DISABLED="✗ Soporte Audio-CD desactivado (faltan herramientas)"
readonly MSG_AUDIO_CD_NOT_INSTALLED="✗ Soporte Audio-CD no instalado"
readonly MSG_VIDEO_DVD_SUPPORT_ENABLED="✓ Soporte Vídeo-DVD activado"
readonly MSG_VIDEO_DVD_SUPPORT_DISABLED="✗ Soporte Vídeo-DVD desactivado (faltan herramientas)"
readonly MSG_VIDEO_DVD_NOT_INSTALLED="✗ Soporte Vídeo-DVD no instalado"
readonly MSG_BLURAY_SUPPORT_ENABLED="✓ Soporte Blu-ray activado"
readonly MSG_BLURAY_SUPPORT_DISABLED="✗ Soporte Blu-ray desactivado (faltan herramientas)"
readonly MSG_BLURAY_NOT_INSTALLED="✗ Soporte Blu-ray no instalado"

readonly MSG_WARNING_AUDIO_CD_NO_SUPPORT="ADVERTENCIA: Audio-CD detectado, pero no hay soporte instalado"
readonly MSG_FALLBACK_DATA_DISC="Alternativa: Copiar como disco de datos"
readonly MSG_START_COPY_PROCESS="Inicio de la copia:"
readonly MSG_ERROR_AUDIO_CD_NOT_AVAILABLE="ERROR: Soporte Audio-CD no disponible"
readonly MSG_ERROR_VIDEO_DVD_NOT_AVAILABLE="ERROR: Soporte Vídeo-DVD no disponible"
readonly MSG_ERROR_BLURAY_NOT_AVAILABLE="ERROR: Soporte Blu-ray no disponible"

# Errores de dependencias
readonly MSG_ERROR_CRITICAL_TOOLS_MISSING="ERROR: Faltan herramientas críticas:"
readonly MSG_INSTALLATION_CORE_TOOLS="Instalación: apt-get install coreutils util-linux eject"

# ============================================================================
# FLUJO DE TRABAJO
# ============================================================================

readonly MSG_DISK2ISO_STARTED="disk2iso iniciado"
readonly MSG_OUTPUT_DIRECTORY="Directorio de salida:"
readonly MSG_DRIVE_MONITORING_STARTED="Monitoreo de unidad iniciado"
readonly MSG_MEDIUM_DETECTED="Medio insertado detectado"
readonly MSG_DISC_TYPE_DETECTED="Tipo de disco detectado:"
readonly MSG_VOLUME_LABEL="Etiqueta de volumen:"
readonly MSG_UNMOUNTING_DISC="Desmontando disco para acceso directo..."
readonly MSG_DISC_EJECTED="✓ Medio expulsado"
readonly MSG_EJECT_FAILED="⚠ Expulsión fallida - retire manualmente"
readonly MSG_WAITING_FOR_REMOVAL="Esperando extracción del medio..."
readonly MSG_WAITING_FOR_MEDIUM="Esperando medio..."
readonly MSG_DRIVE_DETECTED="Unidad detectada:"
readonly MSG_SEARCHING_USB_DRIVE="Buscando unidad USB... (Intento"
readonly MSG_OF_ATTEMPTS="/"
readonly MSG_ERROR_NO_DRIVE_FOUND="ERROR: Ninguna unidad detectada después de"
readonly MSG_ATTEMPTS="intentos"
readonly MSG_DRIVE_NOT_AVAILABLE="Unidad no disponible:"
readonly MSG_COPY_SUCCESS_FINAL="Copia exitosa:"
readonly MSG_COPY_FAILED_FINAL="Copia fallida:"

# ============================================================================
# ESPACIO EN DISCO
# ============================================================================

readonly MSG_WARNING_DISK_SPACE_CHECK_FAILED="ADVERTENCIA: No se pudo determinar el espacio en disco"
readonly MSG_DISK_SPACE_INFO="Espacio en disco:"
readonly MSG_DISK_SPACE_MB_AVAILABLE="MB disponibles,"
readonly MSG_DISK_SPACE_MB_REQUIRED="MB requeridos"
readonly MSG_ERROR_INSUFFICIENT_DISK_SPACE="ERROR: ¡Espacio en disco insuficiente! Requerido:"
readonly MSG_DISK_SPACE_MB_AVAILABLE_SHORT="MB, Disponible:"

# ============================================================================
# DEPENDENCIAS
# ============================================================================

readonly MSG_OPTIONAL_TOOLS_INFO="INFO: Herramientas opcionales para mejor rendimiento:"
readonly MSG_INSTALL_GENISOIMAGE_GDDRESCUE="Instalación: apt-get install genisoimage gddrescue"

# ============================================================================
# MÉTODOS
# ============================================================================

readonly MSG_METHOD_DDRESCUE="Método: Copia robusta"

# ============================================================================
# PROCESO DE COPIA (DISCO DE DATOS)
# ============================================================================

readonly MSG_ISO_VOLUME_DETECTED="Volumen ISO detectado:"
readonly MSG_ISO_BLOCKS="bloques"
readonly MSG_ISO_BLOCKS_SIZE="bloques de"
readonly MSG_ISO_BYTES="bytes"

readonly MSG_COPYING_COMPLETE_DISC="Copiando disco completo (isoinfo no disponible)"
readonly MSG_DATA_PROGRESS="Progreso disco de datos:"
readonly MSG_DATA_DISC_SUCCESS_DDRESCUE="✓ Disco de datos copiado exitosamente"
readonly MSG_ERROR_DDRESCUE_FAILED="ERROR: ddrescue falló"

readonly MSG_PROGRESS="Progreso:"
readonly MSG_PROGRESS_OF="MB /"
readonly MSG_PROGRESS_MB="MB"

# ============================================================================
# MENSAJES DE ESTADO
# ============================================================================

readonly MSG_STATUS_WAITING_DRIVE="Esperando unidad..."
readonly MSG_STATUS_DRIVE_DETECTED="Unidad detectada"
readonly MSG_STATUS_WAITING_MEDIA="Esperando medio..."

# ============================================================================
# ARCHIVOS TEMPORALES
# ============================================================================

readonly MSG_WARNING_TEMP_DIR_DELETE_FAILED="⚠ No se pudo eliminar el directorio temporal, intentando con permisos elevados"
readonly MSG_REMAINING="Restante"
readonly MSG_COPIED="copiado"
