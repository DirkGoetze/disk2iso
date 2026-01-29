/**
 * disk2iso - Configuration Page JavaScript
 * Version: 1.2.0 - Neue Architektur mit Change-Tracking
 */

// Globale Variablen
const changedValues = {};
const originalValues = {};

/**
 * Lädt Config-Werte vom Server
 */
function loadConfig() {
    console.log('loadConfig() wird aufgerufen...');
    fetch('/api/config')
        .then(response => response.json())
        .then(data => {
            console.log('Config geladen:', data);
            
            // Setze Werte und speichere Originale (außer MQTT - wird vom Widget gehandelt)
            setFieldValue('output_dir', data.output_dir || '/media/iso', 'DEFAULT_OUTPUT_DIR');
            setFieldValue('mp3_quality', data.mp3_quality || 2, 'MP3_QUALITY');
            setFieldValue('ddrescue_retries', data.ddrescue_retries || 1, 'DDRESCUE_RETRIES');
            setFieldValue('usb_detection_attempts', data.usb_detection_attempts || 5, 'USB_DRIVE_DETECTION_ATTEMPTS');
            setFieldValue('usb_detection_delay', data.usb_detection_delay || 10, 'USB_DRIVE_DETECTION_DELAY');
            setFieldValue('tmdb_api_key', data.tmdb_api_key || '', 'TMDB_API_KEY');
            
            updateSaveButtonState();
        })
        .catch(error => {
            console.error('Fehler beim Laden der Konfiguration:', error);
            showMessage('Fehler beim Laden der Konfiguration', 'error');
        });
}

/**
 * Setzt Feldwert und speichert Original
 */
function setFieldValue(fieldId, value, configKey, isCheckbox = false) {
    const field = document.getElementById(fieldId);
    if (!field) return;
    
    if (isCheckbox) {
        field.checked = value;
    } else {
        field.value = value;
    }
    
    // Setze data-config-key Attribut
    field.setAttribute('data-config-key', configKey);
    
    // Speichere Original-Wert
    originalValues[configKey] = isCheckbox ? value : value.toString();
    
    // Registriere Event-Listener
    if (!field.hasAttribute('data-listener-attached')) {
        if (isCheckbox) {
            field.addEventListener('change', handleFieldChange);
        } else {
            field.addEventListener('blur', handleFieldChange);
        }
        field.setAttribute('data-listener-attached', 'true');
    }
}

/**
 * Handler für Feld-Änderungen
 */
function handleFieldChange(event) {
    const field = event.target;
    const configKey = field.getAttribute('data-config-key');
    
    if (!configKey) return;
    
    let newValue, originalValue;
    
    if (field.type === 'checkbox') {
        newValue = field.checked;
        originalValue = originalValues[configKey];
    } else {
        newValue = field.value;
        originalValue = originalValues[configKey];
    }
    
    // Vergleiche: Wurde geändert?
    if (newValue.toString() !== originalValue.toString()) {
        changedValues[configKey] = newValue;
        field.classList.add('changed');
    } else {
        delete changedValues[configKey];
        field.classList.remove('changed');
    }
    
    updateSaveButtonState();
}

/**
 * Speichert nur geänderte Werte
 */
function saveConfig() {
    if (Object.keys(changedValues).length === 0) {
        showMessage('Keine Änderungen zum Speichern', 'info');
        return;
    }
    
    // Prüfe ob ein Kopiervorgang läuft und ob ein Neustart erforderlich ist
    fetch('/api/live_status')
        .then(response => response.json())
        .then(status => {
            // Prüfe ob Änderungen einen Neustart erfordern (alle außer Web-UI Einstellungen)
            const requiresRestart = Object.keys(changedValues).some(key => 
                !key.startsWith('WEB_') && key !== 'LANGUAGE'
            );
            
            if (requiresRestart && (status.status === 'copying' || status.status === 'analyzing')) {
                const confirmMsg = `⚠️ ACHTUNG!\n\nEin Kopiervorgang läuft gerade!\n\nDie Änderungen erfordern einen Service-Neustart. Wenn Sie jetzt speichern, gehen alle Daten des laufenden Kopiervorgangs verloren.\n\nMöchten Sie trotzdem fortfahren?`;
                
                if (!confirm(confirmMsg)) {
                    return;
                }
            }
            
            // Speichern durchführen
            performSave();
        })
        .catch(error => {
            console.error('Fehler beim Status-Abruf:', error);
            // Fallback: Speichern ohne Warnung
            performSave();
        });
}

function performSave() {
    const saveButton = document.getElementById('save-config-button');
    if (saveButton) {
        saveButton.disabled = true;
        saveButton.textContent = 'Speichert...';
    }
    
    console.log('saveConfig() - Sende nur Änderungen:', changedValues);
    
    fetch('/api/config', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(changedValues)
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showMessage(`Konfiguration gespeichert (${data.processed} Werte)`, 'success');
            
            // Reset: Neue Original-Werte setzen
            Object.keys(changedValues).forEach(key => {
                originalValues[key] = changedValues[key].toString();
                const field = document.querySelector(`[data-config-key="${key}"]`);
                if (field) {
                    field.classList.remove('changed');
                }
            });
            
            // Zeige Restart-Info
            if (data.restart_info) {
                const restartInfo = data.restart_info;
                if (restartInfo.disk2iso_restarted || restartInfo.disk2iso_web_restarted) {
                    let msg = 'Services neu gestartet: ';
                    if (restartInfo.disk2iso_restarted) msg += 'disk2iso ';
                    if (restartInfo.disk2iso_web_restarted) msg += 'disk2iso-web';
                    showMessage(msg, 'info');
                }
            }
            
            // Leere Änderungs-Array
            Object.keys(changedValues).forEach(key => delete changedValues[key]);
            updateSaveButtonState();
        } else {
            const errorMsg = data.message || 'Unbekannter Fehler';
            showMessage(`Fehler: ${errorMsg}`, 'error');
            if (data.errors) {
                console.error('Detaillierte Fehler:', data.errors);
            }
        }
    })
    .catch(error => {
        console.error('Fehler beim Speichern:', error);
        showMessage(`Netzwerkfehler: ${error.message}`, 'error');
    })
    .finally(() => {
        if (saveButton) {
            saveButton.disabled = false;
            updateSaveButtonState();
        }
    });
}

/**
 * Update Save-Button Status
 */
function updateSaveButtonState() {
    const saveButton = document.getElementById('save-config-button');
    if (!saveButton) return;
    
    const changeCount = Object.keys(changedValues).length;
    const hasChanges = changeCount > 0;
    
    saveButton.disabled = !hasChanges;
    saveButton.textContent = hasChanges 
        ? `Speichern (${changeCount} Änderung${changeCount > 1 ? 'en' : ''})` 
        : 'Speichern';
}

/**
 * Toggle MQTT Felder
 */
function toggleMqttFields() {
    const mqttEnabled = document.getElementById('mqtt_enabled').checked;
    const mqttFields = document.querySelectorAll('.mqtt-field');
    
    mqttFields.forEach(field => {
        field.disabled = !mqttEnabled;
        if (!mqttEnabled) {
            field.style.opacity = '0.5';
        } else {
            field.style.opacity = '1';
        }
    });
}

/**
 * Zeige Nachricht
 */
function showMessage(message, type) {
    const alertContainer = document.getElementById('alert-container');
    if (!alertContainer) return;
    
    const alertDiv = document.createElement('div');
    alertDiv.className = `alert alert-${type}`;
    alertDiv.textContent = message;
    
    alertContainer.innerHTML = '';
    alertContainer.appendChild(alertDiv);
    
    setTimeout(() => {
        alertDiv.remove();
    }, 5000);
}

// ============================================================================
// Directory Browser Functions (aus alter config.js übernommen)
// ============================================================================

function openDirectoryBrowser() {
    const currentOutputDir = document.getElementById('output_dir').value || '/';
    loadDirectories(currentOutputDir);
    
    const modal = document.getElementById('directoryModal');
    if (modal) {
        modal.style.display = 'block';
    }
}

function closeDirectoryBrowser() {
    const modal = document.getElementById('directoryModal');
    if (modal) {
        modal.style.display = 'none';
    }
}

let currentBrowserPath = '/';

function loadDirectories(path) {
    currentBrowserPath = path;
    
    fetch('/api/browse_directories', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ path: path })
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            renderDirectoryList(data.current_path, data.directories, data.writable);
        } else {
            showMessage(`Fehler: ${data.message}`, 'error');
        }
    })
    .catch(error => {
        showMessage(`Fehler beim Laden der Verzeichnisse: ${error.message}`, 'error');
    });
}

function renderDirectoryList(currentPath, directories, writable) {
    const pathDisplay = document.getElementById('currentPath');
    const dirList = document.getElementById('directoryList');
    const selectBtn = document.getElementById('selectDirectoryBtn');
    
    if (pathDisplay) {
        pathDisplay.textContent = currentPath;
    }
    
    if (selectBtn) {
        selectBtn.disabled = !writable;
        selectBtn.title = writable ? 'Diesen Ordner wählen' : 'Ordner nicht beschreibbar';
    }
    
    if (dirList) {
        dirList.innerHTML = '';
        
        // Parent directory (..)
        if (currentPath !== '/') {
            const parentItem = document.createElement('div');
            parentItem.className = 'directory-item';
            parentItem.innerHTML = '<span class="dir-icon">📁</span><span class="dir-name">..</span>';
            parentItem.onclick = () => {
                const parentPath = currentPath.split('/').slice(0, -1).join('/') || '/';
                loadDirectories(parentPath);
            };
            dirList.appendChild(parentItem);
        }
        
        // Subdirectories
        directories.forEach(dir => {
            const dirItem = document.createElement('div');
            dirItem.className = 'directory-item';
            dirItem.innerHTML = `<span class="dir-icon">📁</span><span class="dir-name">${dir}</span>`;
            dirItem.onclick = () => {
                const newPath = currentPath === '/' ? `/${dir}` : `${currentPath}/${dir}`;
                loadDirectories(newPath);
            };
            dirList.appendChild(dirItem);
        });
    }
}

function selectCurrentDirectory() {
    const outputDirField = document.getElementById('output_dir');
    const oldValue = outputDirField.value;
    
    outputDirField.value = currentBrowserPath;
    
    // Triggere Änderungs-Logik
    const configKey = outputDirField.getAttribute('data-config-key');
    if (currentBrowserPath !== originalValues[configKey]) {
        changedValues[configKey] = currentBrowserPath;
        outputDirField.classList.add('changed');
    } else {
        delete changedValues[configKey];
        outputDirField.classList.remove('changed');
    }
    
    updateSaveButtonState();
    closeDirectoryBrowser();
}

// ============================================================================
// Password Toggle Functions (aus alter config.js übernommen)
// ============================================================================

let passwordHideTimer = null;

function togglePasswordVisibility(fieldId) {
    const input = document.getElementById(fieldId);
    const icon = document.getElementById(fieldId + '_icon');
    const button = icon.parentElement;
    
    if (input.type === 'password') {
        input.type = 'text';
        icon.textContent = '🙈';
        button.classList.add('active');
        
        // Auto-Hide nach 20 Sekunden
        if (passwordHideTimer) clearTimeout(passwordHideTimer);
        passwordHideTimer = setTimeout(() => hidePassword(fieldId), 20000);
    } else {
        hidePassword(fieldId);
    }
}

function hidePassword(fieldId) {
    const input = document.getElementById(fieldId);
    const icon = document.getElementById(fieldId + '_icon');
    const button = icon.parentElement;
    
    input.type = 'password';
    icon.textContent = '👁️';
    button.classList.remove('active');
    
    if (passwordHideTimer) {
        clearTimeout(passwordHideTimer);
        passwordHideTimer = null;
    }
}

// ============================================================================
// Initialisierung
// ============================================================================

document.addEventListener('DOMContentLoaded', function() {
    // Lade MQTT Config Widget (wenn verfügbar)
    if (window.mqttConfig) {
        window.mqttConfig.init();
    }
    
    loadConfig();
    
    // Event-Listener für Save-Button
    const saveButton = document.getElementById('save-config-button');
    if (saveButton) {
        saveButton.addEventListener('click', saveConfig);
    }
});
