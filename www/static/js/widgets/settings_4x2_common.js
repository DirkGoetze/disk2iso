/**
 * disk2iso - Settings Widget (4x1) - Common
 * Dynamisches Laden und Verwalten der Kopier-Einstellungen (Audio CD, ddrescue)
 * Auto-Save bei Fokus-Verlust (moderne UX)
 */

(function() {
    'use strict';

    /**
     * Lädt das Common Settings Widget vom Backend
     */
    async function loadCommonSettingsWidget() {
        try {
            const response = await fetch('/api/widgets/common/settings');
            if (!response.ok) throw new Error('Failed to load common settings widget');
            return await response.text();
        } catch (error) {
            console.error('Error loading common settings widget:', error);
            return `<div class="error">Fehler beim Laden der Kopier-Einstellungen: ${error.message}</div>`;
        }
    }

    /**
     * Injiziert das Common Settings Widget in die Config-Seite
     */
    async function injectCommonSettingsWidget() {
        const targetContainer = document.querySelector('#common-settings-container');
        if (!targetContainer) {
            console.warn('Common settings container not found');
            return;
        }

        const widgetHtml = await loadCommonSettingsWidget();
        targetContainer.innerHTML = widgetHtml;
        
        // Event Listener registrieren
        setupEventListeners();
    }

    /**
     * Registriert alle Event Listener für das Common Settings Widget
     */
    function setupEventListeners() {
        // ddrescue Retries - Auto-Save bei Blur
        const ddrescueRetriesField = document.getElementById('ddrescue_retries');
        if (ddrescueRetriesField) {
            ddrescueRetriesField.addEventListener('blur', function() {
                // Nutzt die zentrale handleFieldChange Funktion aus settings.js
                if (window.handleFieldChange) {
                    window.handleFieldChange({ target: ddrescueRetriesField });
                }
            });
        }
    }

    // Auto-Injection beim Laden der Settings-Seite
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', injectCommonSettingsWidget);
    } else {
        injectCommonSettingsWidget();
    }

})();
