#!/bin/bash
################################################################################
# disk2iso - Archivo de idioma español para lib-cd.sh
# Filepath: lang/lib-cd.es
#
# Descripción:
#   Mensajes para las funciones de Audio-CD
#
################################################################################

# ============================================================================
# DEPENDENCIAS
# ============================================================================
# Nota: Mensajes de verificación de herramientas vienen de lib-config.es (MSG_CONFIG_*)
# Solo mensajes específicos del módulo aquí

readonly MSG_CDTEXT_FALLBACK_AVAILABLE="Alternativa CD-TEXT disponible"
readonly MSG_CDTEXT_FALLBACK_INSTALL_HINT="Sugerencia: Para alternativa CD-TEXT instalar: icedax o libcdio-utils (cd-info)"
readonly MSG_AUDIO_SUPPORT_AVAILABLE="Soporte Audio-CD disponible"

# ============================================================================
# METADATOS
# ============================================================================

readonly MSG_TRY_CDTEXT="Intentando leer CD-TEXT..."
readonly MSG_CDTEXT_FOUND="CD-TEXT encontrado:"
readonly MSG_NO_CDTEXT_FOUND="No se encontró CD-TEXT o herramientas no disponibles (icedax/cd-info/cdda2wav)"
readonly MSG_USE_CDTEXT_METADATA="Usando metadatos CD-TEXT"
readonly MSG_CONTINUE_NO_METADATA="Continuar sin metadatos"

readonly MSG_RETRIEVE_METADATA="Obteniendo información del CD..."
readonly MSG_WARNING_CDISCID_MISSING="ADVERTENCIA: cd-discid no instalado - consulta de metadatos imposible"
readonly MSG_WARNING_CURL_JQ_MISSING="ADVERTENCIA: curl/jq no instalado - consulta de metadatos imposible"
readonly MSG_ERROR_DISCID_FAILED="ERROR: No se pudo determinar el ID del disco"
readonly MSG_DISCID="ID del disco:"
readonly MSG_TRACKS="Pistas:"
readonly MSG_WARNING_LEADOUT_FAILED="ADVERTENCIA: No se pudo determinar el leadout"

readonly MSG_QUERY_MUSICBRAINZ="Consultando información del CD..."
readonly MSG_WARNING_MUSICBRAINZ_FAILED="ADVERTENCIA: Información del CD no disponible (¿sin red?)"
readonly MSG_WARNING_NO_MUSICBRAINZ_ENTRY="ADVERTENCIA: No se encontró información del CD para el ID de disco:"
readonly MSG_ALBUM="Álbum:"
readonly MSG_ARTIST="Artista:"
readonly MSG_YEAR="Año:"
readonly MSG_MUSICBRAINZ_TRACKS_FOUND="MusicBrainz:"
readonly MSG_COVER_AVAILABLE="Carátula disponible"
readonly MSG_WARNING_INCOMPLETE_METADATA="ADVERTENCIA: Información del CD incompleta"

readonly MSG_WARNING_NO_RELEASE_ID="ADVERTENCIA: No hay ID de lanzamiento para descargar carátula"
readonly MSG_DOWNLOAD_COVER="Descargando carátula del álbum..."
readonly MSG_COVER_DOWNLOADED="Carátula descargada:"
readonly MSG_WARNING_COVER_DOWNLOAD_FAILED="ADVERTENCIA: Descarga de carátula fallida"

# ============================================================================
# CREACIÓN NFO
# ============================================================================

readonly MSG_INFO_NO_MUSICBRAINZ_NFO_SKIPPED="INFO: Sin información de CD - album.nfo omitido"
readonly MSG_CREATE_ALBUM_NFO="Creando album.nfo..."
readonly MSG_NFO_FILE_CREATED="album.nfo creado"

# ============================================================================
# CARÁTULA
# ============================================================================

readonly MSG_ERROR_COVER_COPY_FAILED="ERROR: No se pudo copiar la carátula"
readonly MSG_ERROR_COVER_FILE_NOT_FOUND="ERROR: Archivo de carátula no encontrado:"

# ============================================================================
# COPIA AUDIO-CD
# ============================================================================

readonly MSG_START_AUDIO_RIPPING="Iniciando copia..."
readonly MSG_ERROR_CDPARANOIA_MISSING="ERROR: cdparanoia no instalado"
readonly MSG_ERROR_LAME_MISSING="ERROR: lame no instalado"
readonly MSG_ERROR_GENISOIMAGE_MISSING="ERROR: genisoimage no instalado"
readonly MSG_CONTINUE_WITHOUT_METADATA="Continuar sin metadatos..."
readonly MSG_INFO_EYED3_MISSING="INFO: eyeD3 no instalado - incrustación de carátula omitida"

readonly MSG_ALBUM_DIRECTORY="Directorio del álbum:"

readonly MSG_ERROR_NO_TRACKS="ERROR: No se encontraron pistas"
readonly MSG_TRACKS_FOUND="Pistas encontradas:"

readonly MSG_START_CDPARANOIA_RIPPING="Leyendo pistas de audio..."
readonly MSG_RIPPING_TRACK="Leyendo pista $1 / $2"
readonly MSG_ERROR_TRACK_RIP_FAILED="ERROR: No se pudo leer la pista $1"

readonly MSG_ENCODING_TRACK_WITH_TITLE="Codificando pista"
readonly MSG_ENCODING_TRACK="Codificando pista"
readonly MSG_ERROR_MP3_ENCODING_FAILED="ERROR: Codificación MP3 para pista"

readonly MSG_COVER_SAVED_FOLDER_JPG="Carátula guardada como folder.jpg en el directorio del álbum"
readonly MSG_RIPPING_COMPLETE_CREATE_ISO="Copia completada - creando ISO..."
readonly MSG_ERROR_INSUFFICIENT_SPACE_ISO="ERROR: Espacio en disco insuficiente para crear ISO"

readonly MSG_CREATE_ISO="Creando ISO:"
readonly MSG_VOLUME_ID="ID del volumen:"
readonly MSG_ERROR_ISO_CREATION_FAILED="ERROR: Creación de ISO fallida"
readonly MSG_ERROR_ISO_NOT_CREATED="ERROR: El archivo ISO no fue creado"
readonly MSG_ISO_CREATED="ISO creado:"

readonly MSG_CREATE_MD5="Creando suma de verificación MD5..."
readonly MSG_WARNING_MD5_FAILED="ADVERTENCIA: No se pudo crear la suma de verificación MD5"
readonly MSG_AUDIO_CD_SUCCESS="Audio-CD copiado exitosamente y guardado como ISO"
