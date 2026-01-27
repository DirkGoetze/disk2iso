#!/bin/bash
################################################################################
# disk2iso - Archivo de Idioma Español para libmetadb.sh
# Filepath: lang/libmetadb.es
#
# Descripción:
#   Textos de mensajes para funciones de base de datos de metadatos
#
################################################################################

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

readonly MSG_METADB_INIT_SUCCESS="Base de datos de metadatos inicializada para tipo:"
readonly MSG_METADB_INIT_ERROR="ERROR: No se pudo inicializar la base de datos de metadatos"
readonly MSG_METADB_INIT_MISSING_TYPE="ERROR: Falta tipo de disco para inicialización"
readonly MSG_METADB_INIT_UNKNOWN_TYPE="ADVERTENCIA: Tipo de disco desconocido - solo campos base inicializados:"

# ============================================================================
# OPERACIONES CRUD
# ============================================================================

readonly MSG_METADB_SET_SUCCESS="Valor de metadatos establecido:"
readonly MSG_METADB_SET_ERROR="ERROR: No se pudo establecer el valor de metadatos"
readonly MSG_METADB_SET_MISSING_KEY="ERROR: Falta clave para operación set"

readonly MSG_METADB_GET_SUCCESS="Valor de metadatos recuperado:"
readonly MSG_METADB_GET_NOT_FOUND="ADVERTENCIA: Clave no encontrada:"
readonly MSG_METADB_GET_MISSING_KEY="ERROR: Falta clave para operación get"

readonly MSG_METADB_CLEAR_SUCCESS="Base de datos de metadatos borrada"

# ============================================================================
# OPERACIONES DE PISTA
# ============================================================================

readonly MSG_METADB_SET_TRACK_SUCCESS="Información de pista establecida:"
readonly MSG_METADB_SET_TRACK_ERROR="ERROR: No se pudo establecer información de pista"
readonly MSG_METADB_SET_TRACK_INVALID_NUMBER="ERROR: Número de pista inválido:"

readonly MSG_METADB_GET_TRACK_SUCCESS="Información de pista recuperada:"
readonly MSG_METADB_GET_TRACK_NOT_FOUND="ADVERTENCIA: Información de pista no encontrada:"

# ============================================================================
# OPERACIONES DE GÉNERO
# ============================================================================

readonly MSG_METADB_ADD_GENRE_SUCCESS="Género añadido:"
readonly MSG_METADB_ADD_GENRE_ERROR="ERROR: No se pudo añadir género"

readonly MSG_METADB_GET_GENRES_SUCCESS="Géneros recuperados:"
readonly MSG_METADB_GET_GENRES_EMPTY="No hay géneros disponibles"

# ============================================================================
# OPERACIONES DE EXPORTACIÓN
# ============================================================================

readonly MSG_METADB_EXPORT_NFO_SUCCESS="Archivo NFO creado:"
readonly MSG_METADB_EXPORT_NFO_ERROR="ERROR: No se pudo crear archivo NFO"
readonly MSG_METADB_EXPORT_NFO_MISSING_PATH="ERROR: Falta ruta de archivo NFO"
readonly MSG_METADB_EXPORT_NFO_UNKNOWN_TYPE="ERROR: Exportación NFO para tipo de disco desconocido:"

readonly MSG_METADB_EXPORT_JSON_SUCCESS="JSON exportado"
readonly MSG_METADB_EXPORT_JSON_ERROR="ERROR: Exportación JSON falló"

# ============================================================================
# VALIDACIÓN
# ============================================================================

readonly MSG_METADB_VALIDATE_SUCCESS="Validación de metadatos exitosa"
readonly MSG_METADB_VALIDATE_ERROR="ERROR: Validación de metadatos falló"
readonly MSG_METADB_VALIDATE_MISSING_TYPE="ERROR: disc_type falta"
readonly MSG_METADB_VALIDATE_MISSING_LABEL="ADVERTENCIA: disc_label falta"
readonly MSG_METADB_VALIDATE_AUDIO_MISSING="ADVERTENCIA: CD de audio sin artista/álbum"
readonly MSG_METADB_VALIDATE_VIDEO_MISSING="ADVERTENCIA: Video sin título"

# ============================================================================
# FUNCIONES AUXILIARES
# ============================================================================

readonly MSG_METADB_SANITIZE_SUCCESS="Nombre de archivo sanitizado:"
readonly MSG_METADB_DUMP_HEADER="=== Volcado de Metadatos ==="

################################################################################
# FIN libmetadb.es
################################################################################
