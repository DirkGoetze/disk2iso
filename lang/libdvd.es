#!/bin/bash
################################################################################
# disk2iso - Archivo de idioma español para lib-dvd.sh
# Filepath: lang/lib-dvd.es
#
# Descripción:
#   Mensajes para las funciones de Vídeo-DVD
#
################################################################################

# ============================================================================
# DEPENDENCIAS
# ============================================================================
# Nota: Mensajes de verificación de herramientas vienen de lib-config.es (MSG_CONFIG_*)
# Solo mensajes específicos del módulo aquí

readonly MSG_VIDEO_SUPPORT_AVAILABLE="Soporte de Video-DVD/BD disponible"

# ============================================================================
# MÉTODO DVDBACKUP
# ============================================================================

readonly MSG_METHOD_DVDBACKUP="Método: Copia descifrada"
readonly MSG_DVD_SIZE="Tamaño del DVD:"
readonly MSG_EXTRACT_DVD_STRUCTURE="Copiando contenido del DVD..."
readonly MSG_ERROR_DVDBACKUP_FAILED="ERROR: dvdbackup falló"
readonly MSG_DVD_MARKED_FOR_RETRY="ℹ El DVD se reintentará con ddrescue en el próximo intento"
readonly MSG_WARNING_DVD_FAILED_BEFORE="⚠ Este DVD falló en el último intento"
readonly MSG_FALLBACK_TO_DDRESCUE="→ Cambio automático a ddrescue (método tolerante a errores)"
readonly MSG_ERROR_DVD_REJECTED="✗ DVD rechazado: Ya falló 2 veces"
readonly MSG_ERROR_DVD_REJECTED_HINT="Sugerencia: Limpiar/reemplazar DVD y eliminar archivo .failed_dvds para reiniciar"
readonly MSG_DVD_FINAL_FAILURE="✗ DVD falló definitivamente - será rechazado en la próxima inserción"
readonly MSG_DVD_STRUCTURE_EXTRACTED="✓ Contenido del DVD copiado (100%)"
readonly MSG_ERROR_NO_VIDEO_TS="ERROR: No se encontró carpeta VIDEO_TS"
readonly MSG_CREATE_DECRYPTED_ISO="Creando archivo ISO..."
readonly MSG_DECRYPTED_DVD_SUCCESS="✓ ISO Vídeo-DVD creado exitosamente"
readonly MSG_ERROR_GENISOIMAGE_FAILED="ERROR: genisoimage falló"

# ============================================================================
# MÉTODO DDRESCUE
# ============================================================================

readonly MSG_VIDEO_DVD_DDRESCUE_SUCCESS="✓ Vídeo-DVD copiado exitosamente"
readonly MSG_DVD_PROGRESS="Progreso Vídeo-DVD:"
