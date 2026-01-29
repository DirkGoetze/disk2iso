/**
 * disk2iso - MQTT Config Widget
 * Dynamisches Laden und Verwalten der MQTT-Konfiguration
 * Auto-Save bei Fokus-Verlust (moderne UX)
 */

(function() {
    'use strict';

    let passwordHideTimer = null;
    let saveIndicator = null;

    /**
     * Lädt das MQTT Config Widget vom Backend
     */
    async function loadMqttConfigWidget() {
        try {
            const response = await fetch('/api/mqtt/config');
            if (!response.ok) throw new Error('Failed to load MQTT config widget');
            return await response.text();
        } catch (error) {
            console.error('Error loading MQTT config widget:', error);
            return `<div class="error">Fehler beim Laden der MQTT-Konfiguration: ${error.message}</div>`;
        }
    }

    /**
     * Injiziert das MQTT Config Widget in die Config-Seite
     */
    async function injectMqttConfigWidget() {
        const targetContainer = document.querySelector('#mqtt-config-container');
        if (!targetContainer) {
            console.warn('MQTT config container not found');
            return;
        }

        const widgetHtml = await loadMqttConfigWidget();
        targetContainer.innerHTML = widgetHtml;
        
        // Save-Indicator erstellen
        createSaveIndicator();
        
        // Event Listener registrieren
        setupEventListeners();
    }

    /**
     * Erstellt den Save-Indicator für visuelles Feedback
     */
    function createSaveIndicator() {
        saveIndicator = document.createElement('div');
        saveIndicator.id = 'mqtt-save-indicator';
        saveIndicator.style.cssText = `
            position: fixed;
            top: 80px;
            right: 20px;
            padding: 12px 20px;
            border-radius: 8px;
            background: #3498db;
            color: white;
            font-weight: 600;
            box-shadow: 0 4px 12px rgba(0,0,0,0.2);
            display: none;
            z-index: 2000;
            transition: all 0.3s ease;
        `;
        document.body.appendChild(saveIndicator);
    }

    /**
     * Zeigt Save-Indicator mit Status
     */
    function showSaveIndicator(message, type = 'saving') {
        if (!saveIndicator) return;
        
        const colors = {
            saving: '#3498db',
            success: '#27ae60',
            error: '#e74c3c'
        };
        
        saveIndicator.style.background = colors[type] || colors.saving;
        saveIndicator.textContent = message;
        saveIndicator.style.display = 'block';
        
        // Auto-hide bei Success/Error nach 3 Sekunden
        if (type !== 'saving') {
            setTimeout(() => {
                saveIndicator.style.display = 'none';
            }, 3000);
        }
    }

    /**
     * Registriert alle Event Listener für das Config Widget
     * Auto-Save bei Fokus-Verlust
     */
    function setupEventListeners() {
        // MQTT Enable/Disable Toggle - sofort speichern
        const mqttEnabledCheckbox = document.getElementById('mqtt_enabled');
        if (mqttEnabledCheckbox) {
            mqttEnabledCheckbox.addEventListener('change', function() {
                const mqttSettings = document.getElementById('mqtt-settings');
                if (mqttSettings) {
                    mqttSettings.style.display = this.checked ? 'block' : 'none';
                }
                // Auto-Save
                autoSaveMqttConfig();
            });
        }

        // MQTT Auth Enable/Disable Toggle - sofort speichern
        const mqttAuthCheckbox = document.getElementById('mqtt_auth_enabled');
        if (mqttAuthCheckbox) {
            mqttAuthCheckbox.addEventListener('change', function() {
                const authSettings = document.getElementById('mqtt-auth-settings');
                if (authSettings) {
                    authSettings.style.display = this.checked ? 'block' : 'none';
                }
                
                // Username/Password clearen wenn Auth disabled
                if (!this.checked) {
                    const userInput = document.getElementById('mqtt_user');
                    const passwordInput = document.getElementById('mqtt_password');
                    if (userInput) userInput.value = '';
                    if (passwordInput) passwordInput.value = '';
                }
                
                // Auto-Save
                autoSaveMqttConfig();
            });
        }

        // Auto-Save bei Fokus-Verlust für Text/Number Inputs
        const autoSaveFields = ['mqtt_broker', 'mqtt_port', 'mqtt_user', 'mqtt_password'];
        autoSaveFields.forEach(fieldId => {
            const field = document.getElementById(fieldId);
            if (field) {
                field.addEventListener('blur', () => {
                    autoSaveMqttConfig();
                });
            }
        });
    }

    /**
     * Auto-Save: Speichert MQTT-Konfiguration automatisch
     */
    async function autoSaveMqttConfig() {
        const config = collectMqttConfig();
        
        showSaveIndicator('💾 Speichere MQTT-Einstellungen...', 'saving');
        
        try {
            const response = await fetch('/api/mqtt/save', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(config)
            });
            
            const result = await response.json();
            
            if (result.success) {
                showSaveIndicator('✅ MQTT-Einstellungen gespeichert', 'success');
                
                // Restart-Info anzeigen falls nötig
                if (result.restart_required) {
                    showRestartNotification();
                }
            } else {
                showSaveIndicator('❌ Fehler beim Speichern', 'error');
                console.error('Save failed:', result.error);
            }
        } catch (error) {
            showSaveIndicator('❌ Verbindungsfehler', 'error');
            console.error('Error saving MQTT config:', error);
        }
    }

    /**
     * Zeigt Restart-Benachrichtigung
     */
    function showRestartNotification() {
        const notification = document.createElement('div');
        notification.style.cssText = `
            position: fixed;
            bottom: 20px;
            right: 20px;
            padding: 15px 20px;
            background: #f39c12;
            color: white;
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.2);
            max-width: 300px;
            z-index: 2000;
            animation: slideIn 0.3s ease;
        `;
        notification.innerHTML = `
            <strong>⚠️ Service-Neustart erforderlich</strong>
            <p style="margin: 8px 0 0 0; font-size: 0.9em;">
                Die Änderungen werden nach einem Service-Neustart aktiv.
            </p>
        `;
        document.body.appendChild(notification);
        
        // Auto-remove nach 8 Sekunden
        setTimeout(() => {
            notification.style.opacity = '0';
            setTimeout(() => notification.remove(), 300);
        }, 8000);
    }

    /**
     * Testet die MQTT-Verbindung
     */
    window.testMqttConnection = async function() {
        const resultSpan = document.getElementById('mqtt-test-result');
        const testBtn = document.getElementById('mqtt-test-btn');
        
        if (!resultSpan || !testBtn) return;
        
        // Button deaktivieren während Test läuft
        testBtn.disabled = true;
        testBtn.textContent = '🔄 Teste Verbindung...';
        resultSpan.textContent = '';
        resultSpan.className = '';
        
        try {
            const config = {
                broker: document.getElementById('mqtt_broker').value,
                port: parseInt(document.getElementById('mqtt_port').value),
                user: document.getElementById('mqtt_auth_enabled').checked ? document.getElementById('mqtt_user').value : '',
                password: document.getElementById('mqtt_auth_enabled').checked ? document.getElementById('mqtt_password').value : ''
            };
            
            const response = await fetch('/api/mqtt/test', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(config)
            });
            
            const result = await response.json();
            
            if (result.success) {
                resultSpan.textContent = '✅ Verbindung erfolgreich';
                resultSpan.className = 'badge success';
            } else {
                resultSpan.textContent = '❌ Verbindung fehlgeschlagen: ' + result.error;
                resultSpan.className = 'badge error';
            }
        } catch (error) {
            resultSpan.textContent = '❌ Fehler beim Testen: ' + error.message;
            resultSpan.className = 'badge error';
        } finally {
            testBtn.disabled = false;
            testBtn.textContent = '🔌 Verbindung testen';
            
            // Ergebnis nach 5 Sekunden ausblenden
            setTimeout(() => {
                resultSpan.textContent = '';
                resultSpan.className = '';
            }, 5000);
        }
    };

    /**
     * Toggle Password Visibility mit Auto-Hide nach 20 Sekunden
     */
    window.togglePasswordVisibility = function(inputId) {
        const input = document.getElementById(inputId);
        const icon = document.getElementById(inputId + '_icon');
        const button = icon.parentElement;
        
        if (!input || !icon) return;
        
        // Clear existing timer
        if (passwordHideTimer) {
            clearTimeout(passwordHideTimer);
            passwordHideTimer = null;
        }
        
        if (input.type === 'password') {
            input.type = 'text';
            icon.textContent = '🙈';
            button.classList.add('active');
            
            // Auto-hide nach 20 Sekunden
            passwordHideTimer = setTimeout(() => {
                input.type = 'password';
                icon.textContent = '👁️';
                button.classList.remove('active');
                passwordHideTimer = null;
            }, 20000);
        } else {
            input.type = 'password';
            icon.textContent = '👁️';
            button.classList.remove('active');
        }
    };

    /**
     * Sammelt MQTT-Konfigurationsdaten aus dem Formular
     */
    function collectMqttConfig() {
        const mqttEnabled = document.getElementById('mqtt_enabled').checked;
        const authEnabled = document.getElementById('mqtt_auth_enabled').checked;
        
        return {
            mqtt_enabled: mqttEnabled,
            mqtt_broker: document.getElementById('mqtt_broker').value,
            mqtt_port: parseInt(document.getElementById('mqtt_port').value) || 1883,
            mqtt_user: authEnabled ? document.getElementById('mqtt_user').value : '',
            mqtt_password: authEnabled ? document.getElementById('mqtt_password').value : ''
        };
    }

    /**
     * Exportiert Funktionen für externen Zugriff
     */
    window.mqttConfig = {
        init: injectMqttConfigWidget,
        collectConfig: collectMqttConfig,
        testConnection: window.testMqttConnection,
        save: autoSaveMqttConfig
    };

})();
