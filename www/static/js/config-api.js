/**
 * Config Management - Field-by-Field API
 * 
 * Neue Architektur: Jedes Feld speichert sofort beim Verlassen (onBlur/onChange)
 * Kein "Speichern"-Button mehr nötig
 */

/**
 * Liest einzelnen Config-Wert von der API
 * @param {string} key - Config-Key (z.B. "DEFAULT_OUTPUT_DIR")
 * @returns {Promise<string>} - Config-Wert
 */
async function getConfigValue(key) {
    try {
        const response = await fetch(`/api/config/${key}`);
        const data = await response.json();
        
        if (data.success) {
            return data.value;
        } else {
            throw new Error(data.message || 'Failed to read config');
        }
    } catch (error) {
        console.error(`Error reading config key ${key}:`, error);
        throw error;
    }
}

/**
 * Schreibt einzelnen Config-Wert in die API
 * Optional: Triggert Service-Restart wenn erforderlich
 * @param {string} key - Config-Key (z.B. "DEFAULT_OUTPUT_DIR")
 * @param {string|number} value - Neuer Wert
 * @returns {Promise<object>} - Response mit restart_required Flag
 */
async function setConfigValue(key, value) {
    try {
        const response = await fetch(`/api/config/${key}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ value: value })
        });
        
        const data = await response.json();
        
        if (data.success) {
            // Optional: Zeige Benachrichtigung wenn Service neu gestartet wurde
            if (data.restart_required) {
                if (data.restart_failed) {
                    showToast(`Gespeichert, aber Service-Neustart fehlgeschlagen`, 'warning');
                } else {
                    showToast(`Gespeichert (${data.restart_service} neu gestartet)`, 'success');
                }
            } else {
                showToast('Gespeichert', 'success');
            }
            return data;
        } else {
            throw new Error(data.message || 'Failed to write config');
        }
    } catch (error) {
        console.error(`Error writing config key ${key}:`, error);
        showToast(`Fehler beim Speichern: ${error.message}`, 'error');
        throw error;
    }
}

/**
 * Legacy: Liest alle Config-Werte auf einmal (Batch)
 * DEPRECATED für neue Implementierungen - Nutze getConfigValue() stattdessen
 * @returns {Promise<object>} - Alle Config-Werte
 */
async function getAllConfigValues() {
    try {
        const response = await fetch('/api/config/all');
        const data = await response.json();
        
        if (data.success) {
            return data;
        } else {
            throw new Error(data.message || 'Failed to read all config');
        }
    } catch (error) {
        console.error('Error reading all config values:', error);
        throw error;
    }
}

/**
 * Initialisiert ein Config-Feld für field-by-field Speicherung
 * @param {string} elementId - DOM-Element ID
 * @param {string} configKey - Config-Key in disk2iso.conf
 * @param {string} defaultValue - Default-Wert falls nicht gesetzt
 */
async function initConfigField(elementId, configKey, defaultValue = '') {
    const element = document.getElementById(elementId);
    if (!element) {
        console.warn(`Element #${elementId} not found`);
        return;
    }
    
    // Lade aktuellen Wert von API
    try {
        const value = await getConfigValue(configKey);
        element.value = value || defaultValue;
    } catch (error) {
        element.value = defaultValue;
    }
    
    // Event-Handler: Speichere bei Änderung (onBlur für Text, onChange für Select)
    if (element.tagName === 'SELECT') {
        element.addEventListener('change', async (e) => {
            await setConfigValue(configKey, e.target.value);
        });
    } else {
        element.addEventListener('blur', async (e) => {
            await setConfigValue(configKey, e.target.value);
        });
    }
}

/**
 * Toast-Notification Helper
 * @param {string} message - Nachricht
 * @param {string} type - 'success' | 'error' | 'warning' | 'info'
 */
function showToast(message, type = 'info') {
    // Prüfe ob Toast-Container existiert
    let container = document.getElementById('toast-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toast-container';
        container.style.cssText = 'position: fixed; top: 20px; right: 20px; z-index: 9999;';
        document.body.appendChild(container);
    }
    
    // Erstelle Toast
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.style.cssText = `
        background: ${type === 'success' ? '#28a745' : type === 'error' ? '#dc3545' : type === 'warning' ? '#ffc107' : '#17a2b8'};
        color: white;
        padding: 12px 20px;
        margin-bottom: 10px;
        border-radius: 4px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.2);
        animation: slideIn 0.3s ease-out;
    `;
    toast.textContent = message;
    
    container.appendChild(toast);
    
    // Auto-Remove nach 3 Sekunden
    setTimeout(() => {
        toast.style.animation = 'slideOut 0.3s ease-in';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// CSS Animation für Toast (injiziere einmalig)
if (!document.getElementById('toast-animations')) {
    const style = document.createElement('style');
    style.id = 'toast-animations';
    style.textContent = `
        @keyframes slideIn {
            from { transform: translateX(400px); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        @keyframes slideOut {
            from { transform: translateX(0); opacity: 1; }
            to { transform: translateX(400px); opacity: 0; }
        }
    `;
    document.head.appendChild(style);
}

/**
 * Beispiel-Nutzung:
 * 
 * // HTML:
 * <input type="text" id="output-dir" />
 * <input type="number" id="ddrescue-retries" />
 * <select id="usb-attempts">
 *   <option value="3">3</option>
 *   <option value="5">5</option>
 *   <option value="10">10</option>
 * </select>
 * 
 * // JavaScript:
 * document.addEventListener('DOMContentLoaded', async () => {
 *     await initConfigField('output-dir', 'DEFAULT_OUTPUT_DIR', '/media/iso');
 *     await initConfigField('ddrescue-retries', 'DDRESCUE_RETRIES', '3');
 *     await initConfigField('usb-attempts', 'USB_DRIVE_DETECTION_ATTEMPTS', '5');
 * });
 */
