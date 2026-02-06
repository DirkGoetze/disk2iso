/**
 * disk2iso - Settings Widget (4x1) - Drivestat
 * Dynamisches Laden und Verwalten der Hardware-Erkennungs-Einstellungen (USB Detection)
 * Auto-Save bei Fokus-Verlust (moderne UX)
 */

(function() {
    'use strict';

    /**
     * Lädt das Drivestat Settings Widget vom Backend
     */
    async function loadDrivestatSettingsWidget() {
        try {
            const response = await fetch('/api/widgets/drivestat/settings');
            if (!response.ok) throw new Error('Failed to load drivestat settings widget');
            return await response.text();
        } catch (error) {
            console.error('Error loading drivestat settings widget:', error);
            return `<div class="error">Fehler beim Laden der Hardware-Einstellungen: ${error.message}</div>`;
        }
    }

    /**
     * Injiziert das Drivestat Settings Widget in die Config-Seite
     */
    async function injectDrivestatSettingsWidget() {
        const targetContainer = document.querySelector('#drivestat-settings-container');
        if (!targetContainer) {
            console.warn('Drivestat settings container not found');
            return;
        }

        const widgetHtml = await loadDrivestatSettingsWidget();
        targetContainer.innerHTML = widgetHtml;
        
        // Event Listener registrieren
        setupEventListeners();
    }

    /**
     * Registriert alle Event Listener für das Drivestat Settings Widget
     */
    function setupEventListeners() {
        // USB Detection Attempts - Auto-Save bei Blur
        const usbAttemptsField = document.getElementById('usb_detection_attempts');
        if (usbAttemptsField) {
            usbAttemptsField.addEventListener('blur', function() {
                // Nutzt die zentrale handleFieldChange Funktion aus settings.js
                if (window.handleFieldChange) {
                    window.handleFieldChange({ target: usbAttemptsField });
                }
            });
        }
        
        // USB Detection Delay - Auto-Save bei Blur
        const usbDelayField = document.getElementById('usb_detection_delay');
        if (usbDelayField) {
            usbDelayField.addEventListener('blur', function() {
                // Nutzt die zentrale handleFieldChange Funktion aus settings.js
                if (window.handleFieldChange) {
                    window.handleFieldChange({ target: usbDelayField });
                }
            });
        }
    }

    // Auto-Injection beim Laden der Settings-Seite
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', injectDrivestatSettingsWidget);
    } else {
        injectDrivestatSettingsWidget();
    }

})();
