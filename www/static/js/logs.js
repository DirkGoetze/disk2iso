/**
 * disk2iso - Logs Page JavaScript
 */

let autoRefreshInterval = null;
let currentLogFile = null;

function loadLogs() {
    const logType = document.getElementById('log-type').value;
    const logContent = document.getElementById('log-content');
    const archivedList = document.getElementById('archived-logs-list');
    
    // Update Log-Typ Anzeige
    document.getElementById('current-log-type').textContent = 
        document.getElementById('log-type').options[document.getElementById('log-type').selectedIndex].text;
    
    if (logType === 'archived') {
        // Zeige verfügbare Log-Dateien
        archivedList.style.display = 'block';
        loadArchivedLogFiles();
        logContent.textContent = 'Bitte wählen Sie eine Log-Datei aus der Liste oben.';
        return;
    } else {
        archivedList.style.display = 'none';
        currentLogFile = null;
    }
    
    logContent.textContent = 'Lade Logs...';
    
    let endpoint = '/api/logs/current';
    if (logType === 'system') {
        endpoint = '/api/logs/system';
    }
    
    fetch(endpoint)
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                displayLogs(data.logs, data.lines);
                document.getElementById('last-update').textContent = new Date().toLocaleString('de-DE');
            } else {
                logContent.textContent = `Fehler: ${data.message || 'Unbekannter Fehler'}`;
                document.getElementById('log-lines').textContent = '0';
            }
        })
        .catch(error => {
            logContent.textContent = `Fehler beim Laden der Logs: ${error}`;
            console.error('Log-Fehler:', error);
        });
}

function loadArchivedLogFiles() {
    fetch('/api/logs/archived')
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                const fileList = document.getElementById('log-files');
                fileList.innerHTML = '';
                
                if (data.files.length === 0) {
                    fileList.innerHTML = '<div class="no-logs">Keine archivierten Logs verfügbar</div>';
                    return;
                }
                
                data.files.forEach(file => {
                    const item = document.createElement('div');
                    item.className = 'log-file-item';
                    item.textContent = file.name;
                    item.title = `${file.size} Bytes - ${file.modified}`;
                    item.onclick = () => loadArchivedLog(file.name);
                    fileList.appendChild(item);
                });
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden der Log-Dateien:', error);
        });
}

function loadArchivedLog(filename) {
    currentLogFile = filename;
    
    // Markiere aktive Datei
    document.querySelectorAll('.log-file-item').forEach(item => {
        if (item.textContent === filename) {
            item.classList.add('active');
        } else {
            item.classList.remove('active');
        }
    });
    
    const logContent = document.getElementById('log-content');
    logContent.textContent = 'Lade Log-Datei...';
    
    fetch(`/api/logs/archived/${encodeURIComponent(filename)}`)
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                displayLogs(data.logs, data.lines);
                document.getElementById('current-log-type').textContent = filename;
                document.getElementById('last-update').textContent = new Date().toLocaleString('de-DE');
            } else {
                logContent.textContent = `Fehler: ${data.message || 'Unbekannter Fehler'}`;
            }
        })
        .catch(error => {
            logContent.textContent = `Fehler beim Laden der Log-Datei: ${error}`;
            console.error('Log-Fehler:', error);
        });
}

function displayLogs(logs, lineCount) {
    const logContent = document.getElementById('log-content');
    document.getElementById('log-lines').textContent = lineCount || logs.split('\n').length;
    
    if (!logs || logs.trim() === '') {
        logContent.innerHTML = '<div class="no-logs">Keine Logs verfügbar</div>';
        return;
    }
    
    // Highlighte Log-Zeilen basierend auf Keywords
    const lines = logs.split('\n');
    const highlightedLines = lines.map(line => {
        let className = '';
        const lowerLine = line.toLowerCase();
        
        // MQTT-Zeilen markieren (zusätzlich zur Log-Level-Klasse)
        const isMqtt = lowerLine.includes('mqtt');
        
        if (lowerLine.includes('error') || lowerLine.includes('fehler') || lowerLine.includes('failed')) {
            className = 'log-line-error';
        } else if (lowerLine.includes('warning') || lowerLine.includes('warnung') || lowerLine.includes('warn')) {
            className = 'log-line-warning';
        } else if (lowerLine.includes('success') || lowerLine.includes('erfolgreich') || lowerLine.includes('completed')) {
            className = 'log-line-success';
        } else if (lowerLine.includes('info') || lowerLine.includes('start')) {
            className = 'log-line-info';
        }
        
        if (isMqtt) {
            className += ' log-line-mqtt';
        }
        
        return `<div class="log-line ${className}">${escapeHtml(line)}</div>`;
    });
    
    logContent.innerHTML = highlightedLines.join('');
    
    // Scrolle zum Ende
    const viewer = document.getElementById('log-viewer');
    viewer.scrollTop = viewer.scrollHeight;
    
    // Wende Filter an
    filterLogs();
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function filterLogs() {
    const searchTerm = document.getElementById('log-search').value.toLowerCase();
    const logLevel = document.getElementById('log-level').value;
    const lines = document.querySelectorAll('.log-line');
    
    lines.forEach(line => {
        const text = line.textContent.toLowerCase();
        let showLine = true;
        
        // Filter nach Suchbegriff
        if (searchTerm && !text.includes(searchTerm)) {
            showLine = false;
        }
        
        // Filter nach Log-Level
        if (showLine && logLevel !== 'all') {
            const isError = line.classList.contains('log-line-error');
            const isWarning = line.classList.contains('log-line-warning');
            const isInfo = line.classList.contains('log-line-info');
            const isMqtt = line.classList.contains('log-line-mqtt');
            
            if (logLevel === 'error' && !isError) {
                showLine = false;
            } else if (logLevel === 'warning' && !isWarning) {
                showLine = false;
            } else if (logLevel === 'info' && !isInfo) {
                showLine = false;
            } else if (logLevel === 'mqtt' && !isMqtt) {
                showLine = false;
            }
        }
        
        line.style.display = showLine ? '' : 'none';
    });
}

function clearLogView() {
    document.getElementById('log-content').innerHTML = '<div class="no-logs">Ansicht geleert. Klicken Sie auf "Aktualisieren" um Logs zu laden.</div>';
    document.getElementById('log-lines').textContent = '0';
}

function downloadLog() {
    const logType = document.getElementById('log-type').value;
    const logContent = document.getElementById('log-content').textContent;
    
    if (!logContent || logContent.includes('Keine Logs')) {
        alert('Keine Logs zum Download verfügbar');
        return;
    }
    
    const blob = new Blob([logContent], { type: 'text/plain' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    let filename = `disk2iso_${logType}_${timestamp}.log`;
    if (currentLogFile) {
        filename = currentLogFile;
    }
    
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);
}

function toggleAutoRefresh() {
    const enabled = document.getElementById('auto-refresh').checked;
    
    if (enabled) {
        autoRefreshInterval = setInterval(loadLogs, 5000);
    } else {
        if (autoRefreshInterval) {
            clearInterval(autoRefreshInterval);
            autoRefreshInterval = null;
        }
    }
}

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', function() {
    loadLogs();
});

// Cleanup bei Seitenwechsel
window.addEventListener('beforeunload', function() {
    if (autoRefreshInterval) {
        clearInterval(autoRefreshInterval);
    }
});
