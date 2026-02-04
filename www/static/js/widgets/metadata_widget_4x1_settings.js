/**
 * ============================================================================
 * disk2iso - Metadata Widget Settings JavaScript
 * ============================================================================
 * Filepath: www/static/js/widgets/metadata_widget_settings.js
 * 
 * Beschreibung:
 *   Client-seitiges JavaScript für das Metadata-Einstellungs-Widget
 *   - Lädt Metadata Framework Konfiguration
 *   - Injiziert Widget in Settings-Seite
 * ============================================================================
 */

/**
 * Injiziert das Metadata Settings Widget ins DOM
 */
async function injectMetadataSettingsWidget() {
    const container = document.getElementById('metadata-settings-container');
    if (!container) {
        console.warn('Metadata settings container nicht gefunden');
        return;
    }

    try {
        // Lade Widget-Template
        const response = await fetch('/api/widgets/metadata/settings');
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.json();
        
        // Injiziere HTML
        container.innerHTML = data.html;

        // Setze Werte aus Config
        if (data.config) {
            // Auswahl-Timeout
            const timeoutField = document.getElementById('metadata-selection-timeout');
            if (timeoutField && data.config.METADATA_SELECTION_TIMEOUT !== undefined) {
                timeoutField.value = data.config.METADATA_SELECTION_TIMEOUT;
            }

            // Cache aktiviert
            const cacheField = document.getElementById('metadata-cache-enabled');
            if (cacheField && data.config.METADATA_CACHE_ENABLED !== undefined) {
                cacheField.value = data.config.METADATA_CACHE_ENABLED;
            }

            // Prüfintervall
            const intervalField = document.getElementById('metadata-check-interval');
            if (intervalField && data.config.METADATA_CHECK_INTERVAL !== undefined) {
                intervalField.value = data.config.METADATA_CHECK_INTERVAL;
            }

            // Default Apply-Funktion
            const applyFuncField = document.getElementById('metadata-default-apply-func');
            if (applyFuncField && data.config.METADATA_DEFAULT_APPLY_FUNC !== undefined) {
                applyFuncField.value = data.config.METADATA_DEFAULT_APPLY_FUNC;
            }
        }

        console.log('Metadata settings widget erfolgreich injiziert');
    } catch (error) {
        console.error('Fehler beim Laden des Metadata settings widgets:', error);
        container.innerHTML = `
            <div class="error-box">
                <i class="fas fa-exclamation-triangle"></i>
                <p>Fehler beim Laden der Metadata-Einstellungen: ${error.message}</p>
            </div>
        `;
    }
}

// Auto-Inject beim Laden der Seite (wenn Container vorhanden)
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectMetadataSettingsWidget);
} else {
    injectMetadataSettingsWidget();
}
