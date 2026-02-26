# ============================================================================
# Archivo de idioma: libdrivestat (Español)
# ============================================================================
# Descripción: Mensajes en español para detección y monitoreo de unidades
# Versión: 1.3.0
# Fecha: 2026-02-26 
# ============================================================================

# Reset/Init
readonly MSG_DEBUG_DRIVESTAT_RESET="Información de la unidad restablecida"

# Análisis
readonly MSG_DEBUG_ANALYSE_START="Iniciando análisis de la unidad óptica"
readonly MSG_DEBUG_ANALYSE_COMPLETE="Análisis de la unidad óptica completado"
readonly MSG_ERROR_NO_DRIVE_FOUND="No se encontró ninguna unidad óptica"
readonly MSG_ERROR_VENDOR_UNKNOWN="Fabricante de la unidad desconocido"
readonly MSG_ERROR_MODEL_UNKNOWN="Modelo de la unidad desconocido"
readonly MSG_ERROR_FIRMWARE_UNKNOWN="Versión de firmware de la unidad desconocida"
readonly MSG_ERROR_BUS_TYPE_UNKNOWN="Tipo de bus de la unidad desconocido"
readonly MSG_ERROR_CAPABILITIES_UNKNOWN="Capacidades de la unidad desconocidas"

# Drive Get/Set/Detect
readonly MSG_DEBUG_DRIVE_FOUND="Unidad óptica encontrada: '%s'"
readonly MSG_ERROR_NO_DRIVE_PATH="No se especificó o encontró ruta de unidad óptica"
readonly MSG_DEBUG_DRIVE_SET="Unidad óptica configurada: '%s'"
readonly MSG_DEBUG_DRIVE_CHANGED="Unidad cambiada: '%s' → '%s'"
readonly MSG_ERROR_INVALID_DRIVE_PATH="Ruta de unidad óptica inválida: '%s'"

# Vendor Get/Set/Detect
readonly MSG_DEBUG_VENDOR_GET="Fabricante de la unidad: '%s'"
readonly MSG_DEBUG_VENDOR_SET="Fabricante de la unidad configurado: '%s'"
readonly MSG_DEBUG_VENDOR_CHANGED="Fabricante cambiado: '%s' → '%s'"

# Model Get/Set/Detect
readonly MSG_DEBUG_MODEL_GET="Modelo de la unidad: '%s'"
readonly MSG_DEBUG_MODEL_SET="Modelo de la unidad configurado: '%s'"
readonly MSG_DEBUG_MODEL_CHANGED="Modelo cambiado: '%s' → '%s'"

# Firmware Get/Set/Detect
readonly MSG_DEBUG_FIRMWARE_GET="Versión de firmware de la unidad: '%s'"
readonly MSG_DEBUG_FIRMWARE_SET="Versión de firmware de la unidad configurada: '%s'"
readonly MSG_DEBUG_FIRMWARE_CHANGED="Versión de firmware cambiada: '%s' → '%s'"

# Bus Type Get/Set/Detect
readonly MSG_DEBUG_BUS_TYPE_GET="Tipo de bus de la unidad: '%s'"
readonly MSG_DEBUG_BUS_TYPE_SET="Tipo de bus de la unidad configurado: '%s'"
readonly MSG_DEBUG_BUS_TYPE_CHANGED="Tipo de bus cambiado: '%s' → '%s'"

# Capabilities Get/Set/Detect
readonly MSG_DEBUG_CAPABILITIES_GET="Capacidades de la unidad: '%s'"
readonly MSG_DEBUG_CAPABILITIES_SET="Capacidades de la unidad configuradas: '%s'"
readonly MSG_DEBUG_CAPABILITIES_CHANGED="Capacidades cambiadas: '%s' → '%s'"

# Closed Status Get/Set/Detect
readonly MSG_DEBUG_CLOSED_GET="Estado 'Unidad cerrada': '%s'"
readonly MSG_ERROR_CLOSED_UNKNOWN="Estado 'Unidad cerrada': desconocido"
readonly MSG_ERROR_CLOSED_INVALID="Valor inválido para 'Unidad cerrada': '%s'"
readonly MSG_ERROR_CLOSED_SET_FAILED="No se pudo establecer el estado 'Unidad cerrada'"
readonly MSG_DEBUG_CLOSED_SET="Estado 'Unidad cerrada' configurado a: '%s'"
readonly MSG_DEBUG_CLOSED_CHANGED="Estado 'Unidad cerrada' cambiado: '%s' → '%s'"
readonly MSG_ERROR_DRIVE_UNKNOWN_CLOSED="Unidad desconocida, no se puede determinar el estado"

# Inserted Status Get/Set/Detect
readonly MSG_DEBUG_INSERTED_GET="Estado 'Medio insertado': '%s'"
readonly MSG_ERROR_INSERTED_UNKNOWN="Estado 'Medio insertado': desconocido"
readonly MSG_ERROR_INSERTED_INVALID="Valor inválido para 'Medio insertado': '%s'"
readonly MSG_ERROR_INSERTED_SET_FAILED="No se pudo establecer el estado 'Medio insertado'"
readonly MSG_DEBUG_INSERTED_SET="Estado 'Medio insertado' configurado a: '%s'"
readonly MSG_DEBUG_INSERTED_CHANGED="Estado 'Medio insertado' cambiado: '%s' → '%s'"

# Overall Status Get/Set/Detect
readonly MSG_DEBUG_STATUS_GET="Estado general de la unidad: '%s'"
readonly MSG_ERROR_STATUS_UNKNOWN="Estado general de la unidad desconocido"
readonly MSG_DEBUG_STATUS_SET="Estado general de la unidad configurado a: '%s'"
readonly MSG_DEBUG_STATUS_CHANGED="Estado general cambiado: '%s' → '%s'"
readonly MSG_DEBUG_STATUS_DETECT="Determinando estado general de la unidad basado en bandeja y estado del medio..."

# Software Info
readonly MSG_ERROR_NO_SOFTWARE_INFO="No se encontró información de software, intentando lectura directa"
readonly MSG_DEBUG_COLLECT_SOFTWARE_START="Recopilando información de software..."
readonly MSG_WARNING_NO_EXTERNAL_DEPS="No se encontraron dependencias externas en INI"
readonly MSG_WARNING_NO_OPTIONAL_DEPS="No se encontraron dependencias opcionales en INI"
readonly MSG_DEBUG_NO_DEPENDENCIES="No hay dependencias configuradas"
readonly MSG_ERROR_SYSTEMINFO_UNAVAILABLE="systeminfo_check_software_list no disponible"
readonly MSG_ERROR_SOFTWARE_CHECK_FAILED="Verificación de software fallida"
readonly MSG_ERROR_JSON_CONVERSION_FAILED="Conversión JSON fallida"
readonly MSG_ERROR_API_WRITE_FAILED="Escritura API fallida"
readonly MSG_DEBUG_COLLECT_SOFTWARE_SUCCESS="Información de software recopilada con éxito"

# Monitor
readonly MSG_DEBUG_MONITOR_STARTED="Monitor de unidad iniciado (PID: %s)"
readonly MSG_DEBUG_MONITOR_STOPPED="Monitor de unidad detenido"
