/**
 * disk2iso - Configuration Page JavaScript
 * Version: 1.2.0
 */

function loadConfig() {
    console.log('loadConfig() wird aufgerufen...');
    fetch('/api/config')
        .then(response => response.json())
        .then(data => {
            console.log('Config geladen:', data);
            document.getElementById('output_dir').value = data.output_dir || '/media/iso';
            document.getElementById('mp3_quality').value = data.mp3_quality || 2;
            document.getElementById('ddrescue_retries').value = data.ddrescue_retries || 1;
            document.getElementById('usb_detection_attempts').value = data.usb_detection_attempts || 5;
            document.getElementById('usb_detection_delay').value = data.usb_detection_delay || 10;
            document.getElementById('mqtt_enabled').checked = data.mqtt_enabled || false;
            document.getElementById('mqtt_broker').value = data.mqtt_broker || '';
            document.getElementById('mqtt_port').value = data.mqtt_port || 1883;
            document.getElementById('mqtt_user').value = data.mqtt_user || '';
            document.getElementById('mqtt_password').value = data.mqtt_password || '';
            document.getElementById('tmdb_api_key').value = data.tmdb_api_key || '';
            console.log('TMDB API Key gesetzt auf:', document.getElementById('tmdb_api_key').value);
            
            toggleMqttFields();
        })
        .catch(error => {
            console.error('Fehler beim Laden der Konfiguration:', error);
            showMessage('Fehler beim Laden der Konfiguration', 'error');
        });
}

function saveConfig() {
    const config = {
        output_dir: document.getElementById('output_dir').value,
        mp3_quality: parseInt(document.getElementById('mp3_quality').value),
        ddrescue_retries: parseInt(document.getElementById('ddrescue_retries').value),
        usb_detection_attempts: parseInt(document.getElementById('usb_detection_attempts').value),
        usb_detection_delay: parseInt(document.getElementById('usb_detection_delay').value),
        mqtt_enabled: document.getElementById('mqtt_enabled').checked,
        mqtt_broker: document.getElementById('mqtt_broker').value,
        mqtt_port: parseInt(document.getElementById('mqtt_port').value),
        mqtt_user: document.getElementById('mqtt_user').value,
        mqtt_password: document.getElementById('mqtt_password').value,
        tmdb_api_key: document.getElementById('tmdb_api_key').value
    };
    
    console.log('saveConfig() wird aufgerufen mit:', config);
    
    fetch('/api/config', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(config)
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showMessage(data.message, 'success');
            
            // Lade Konfiguration neu um anzuzeigen dass sie gespeichert wurde
            setTimeout(() => {
                loadConfig();
            }, 1000);
        } else {
            showMessage(data.message, 'error');
        }
    })
    .catch(error => {
        console.error('Fehler beim Speichern der Konfiguration:', error);
        showMessage('Fehler beim Speichern der Konfiguration', 'error');
    });
}

function restartService() {
    showMessage('Service wird neu gestartet...', 'info');
    // Hier könnte ein API-Call zum Neustarten des Services gemacht werden
    // Für jetzt nur eine Info-Nachricht
    setTimeout(() => {
        showMessage('Konfiguration gespeichert. Bitte starten Sie den Service manuell neu.', 'success');
    }, 1500);
}

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

function showMessage(message, type) {
    const messageDiv = document.getElementById('config-message');
    messageDiv.textContent = message;
    messageDiv.className = 'config-message ' + type;
    messageDiv.style.display = 'block';
    
    // Nachricht nach 5 Sekunden ausblenden
    setTimeout(() => {
        messageDiv.style.display = 'none';
    }, 5000);
}

function resetToDefaults() {
    if (confirm('Möchten Sie wirklich alle Einstellungen auf die Standardwerte zurücksetzen?')) {
        document.getElementById('output_dir').value = '/media/iso';
        document.getElementById('mp3_quality').value = 2;
        document.getElementById('ddrescue_retries').value = 1;
        document.getElementById('usb_detection_attempts').value = 5;
        document.getElementById('usb_detection_delay').value = 10;
        document.getElementById('mqtt_enabled').checked = false;
        document.getElementById('mqtt_broker').value = '';
        document.getElementById('mqtt_port').value = 1883;
        document.getElementById('mqtt_user').value = '';
        document.getElementById('mqtt_password').value = '';
        
        toggleMqttFields();
        showMessage('Einstellungen wurden auf Standardwerte zurückgesetzt (noch nicht gespeichert)', 'info');
    }
}

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', function() {
    loadConfig();
    
    // Event-Listener für MQTT-Toggle
    document.getElementById('mqtt_enabled').addEventListener('change', toggleMqttFields);
    
    // Event-Listener für Formular-Submit
    document.getElementById('config-form').addEventListener('submit', function(e) {
        e.preventDefault(); // Verhindere normalen Form-Submit
        saveConfig();
    });
});

// ============================================================================
// Directory Browser Functions
// ============================================================================

let currentBrowserPath = '/';

function openDirectoryBrowser() {
    const currentOutputDir = document.getElementById('output_dir').value || '/';
    currentBrowserPath = currentOutputDir;
    
    document.getElementById('directoryBrowserModal').style.display = 'block';
    loadDirectories(currentBrowserPath);
}

function closeDirectoryBrowser() {
    document.getElementById('directoryBrowserModal').style.display = 'none';
}

function loadDirectories(path) {
    const listElement = document.getElementById('directoryList');
    const pathElement = document.getElementById('currentPath');
    
    listElement.innerHTML = '<div class="loading">Lade Verzeichnisse...</div>';
    pathElement.textContent = path;
    
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
            currentBrowserPath = data.current_path;
            pathElement.textContent = data.current_path;
            renderDirectoryList(data.directories, data.writable);
        } else {
            listElement.innerHTML = `<div class="error">❌ ${data.message}</div>`;
        }
    })
    .catch(error => {
        console.error('Fehler beim Laden der Verzeichnisse:', error);
        listElement.innerHTML = '<div class="error">❌ Fehler beim Laden der Verzeichnisse</div>';
    });
}

function renderDirectoryList(directories, currentDirWritable) {
    const listElement = document.getElementById('directoryList');
    
    if (directories.length === 0) {
        listElement.innerHTML = '<div class="empty">Keine Unterverzeichnisse vorhanden</div>';
        return;
    }
    
    let html = '<ul class="dir-list">';
    
    directories.forEach(dir => {
        const icon = dir.is_parent ? '⬆️' : '📁';
        const writableIcon = dir.writable ? '✓' : '🔒';
        const writableClass = dir.writable ? 'writable' : 'readonly';
        const writableTitle = dir.writable ? 'Beschreibbar' : 'Nur Lesezugriff';
        
        html += `
            <li class="dir-item ${writableClass}" onclick="loadDirectories('${dir.path}')" title="${writableTitle}">
                <span class="dir-icon">${icon}</span>
                <span class="dir-name">${escapeHtml(dir.name)}</span>
                <span class="dir-writable" title="${writableTitle}">${writableIcon}</span>
            </li>
        `;
    });
    
    html += '</ul>';
    listElement.innerHTML = html;
}

function selectCurrentDirectory() {
    const pathElement = document.getElementById('currentPath');
    const selectedPath = pathElement.textContent;
    
    // Pfad ins Input-Feld übernehmen
    document.getElementById('output_dir').value = selectedPath;
    
    // Modal schließen
    closeDirectoryBrowser();
    
    console.log('Verzeichnis ausgewählt:', selectedPath);
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Modal schließen bei Klick außerhalb
window.onclick = function(event) {
    const modal = document.getElementById('directoryBrowserModal');
    if (event.target === modal) {
        closeDirectoryBrowser();
    }
}
