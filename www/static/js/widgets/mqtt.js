/**
 * MQTT Module - Widget Loader & Status Updater
 * 
 * Funktionen:
 * - Lädt MQTT Service Widget dynamisch in index.html
 * - Aktualisiert MQTT-Status in Echtzeit
 * - Nutzt vorhandene CSS-Klassen (card, info-row, badge, etc.)
 */

(function() {
    'use strict';
    
    /**
     * Lädt MQTT-Widget HTML vom Backend
     * @returns {Promise<string>} HTML-Content des Widgets
     */
    async function loadMqttWidget() {
        try {
            const response = await fetch('/api/mqtt/widget');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            return await response.text();
        } catch (error) {
            console.error('[MQTT] Fehler beim Laden des Widgets:', error);
            return null;
        }
    }
    
    /**
     * Injiziert MQTT-Widget in die Service-Grid
     */
    async function injectMqttWidget() {
        // Finde Service-Grid Container
        const serviceGrid = document.querySelector('.three-column-grid');
        if (!serviceGrid) {
            console.warn('[MQTT] Service-Grid nicht gefunden - Widget wird nicht geladen');
            return;
        }
        
        console.log('[MQTT] Lade Widget...');
        
        // Lade Widget HTML
        const widgetHtml = await loadMqttWidget();
        if (!widgetHtml) {
            console.error('[MQTT] Widget-HTML konnte nicht geladen werden');
            return;
        }
        
        // Erstelle temporären Container für HTML-Parsing
        const temp = document.createElement('div');
        temp.innerHTML = widgetHtml;
        
        // Extrahiere Widget-Element
        const widget = temp.querySelector('#mqtt-service-widget');
        if (!widget) {
            console.error('[MQTT] Widget-Element nicht gefunden im HTML');
            return;
        }
        
        // Injiziere in Grid
        serviceGrid.appendChild(widget);
        console.log('[MQTT] Widget erfolgreich geladen');
    }
    
    /**
     * Aktualisiert MQTT-Status (wird von index.js aufgerufen)
     * @param {object} status - MQTT Status Object { status: 'active', running: true }
     */
    function updateMqttStatus(status) {
        // Prüfe ob Widget existiert
        if (!document.getElementById('mqtt-service-widget')) {
            return;  // Widget nicht geladen
        }
        
        // Update Indicator
        const indicator = document.getElementById('mqtt-indicator');
        if (indicator) {
            indicator.className = 'status-indicator ' + (status.running ? 'running' : 'stopped');
        }
        
        // Update Status Text
        const statusText = document.getElementById('mqtt-status');
        if (statusText) {
            statusText.textContent = status.running ? 'Running' : 'Stopped';
        }
        
        // Update Badge
        const badge = document.getElementById('mqtt-badge');
        if (badge) {
            let badgeClass = 'badge ';
            let badgeText = '';
            
            if (status.status === 'active') {
                badgeClass += 'success';
                badgeText = 'Active';  // TODO: i18n
            } else if (status.status === 'inactive') {
                badgeClass += 'warning';
                badgeText = 'Inactive';
            } else if (status.status === 'error') {
                badgeClass += 'error';
                badgeText = 'Error';
            } else {
                badgeClass += 'warning';
                badgeText = 'Not Installed';
            }
            
            badge.className = badgeClass;
            badge.textContent = badgeText;
        }
        
        // Update Timestamp
        const updated = document.getElementById('mqtt-updated');
        if (updated) {
            const now = new Date();
            updated.textContent = now.toLocaleString('de-DE', {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        }
    }
    
    /**
     * Initialisierung beim Seitenladen
     */
    function initMqtt() {
        console.log('[MQTT] Modul initialisiert');
        
        // Lade Widget nur auf Index-Seite
        if (window.location.pathname === '/' || window.location.pathname === '/index') {
            injectMqttWidget();
        }
    }
    
    // Exportiere Funktionen für globalen Zugriff
    window.mqtt = {
        updateStatus: updateMqttStatus,
        init: initMqtt
    };
    
    // Auto-Init wenn DOM bereit
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initMqtt);
    } else {
        initMqtt();
    }
})();
