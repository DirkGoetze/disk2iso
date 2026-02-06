/**
 * Status Widget (2x1) - Disk2iso-web
 * Lädt dynamisch den Status des disk2iso-web Service
 * Version: 1.0.0
 */

function loadDisk2IsoWebServiceWidget() {
    fetch('/api/widgets/disk2iso-web/status')
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                updateDisk2IsoWebServiceWidget(data);
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden des disk2iso-web Service Status:', error);
        });
}

function updateDisk2IsoWebServiceWidget(data) {
    const indicator = document.getElementById('webui-widget-indicator');
    const status = document.getElementById('webui-widget-status');
    const badge = document.getElementById('webui-widget-badge');
    const updated = document.getElementById('webui-widget-updated');
    
    if (!indicator || !status || !badge || !updated) return;
    
    // Status Indicator
    indicator.className = 'status-indicator ' + (data.running ? 'running' : 'stopped');
    status.textContent = data.running ? 'Running' : 'Stopped';
    
    // Service Status Badge
    let badgeClass = 'badge ';
    let badgeText = '';
    
    if (data.status === 'active') {
        badgeClass += 'success';
        badgeText = 'Aktiv';
    } else if (data.status === 'inactive') {
        badgeClass += 'warning';
        badgeText = 'Inaktiv';
    } else if (data.status === 'error') {
        badgeClass += 'error';
        badgeText = 'Fehler';
    } else {
        badgeClass += 'warning';
        badgeText = 'Nicht installiert';
    }
    
    badge.className = badgeClass;
    badge.textContent = badgeText;
    
    // Timestamp
    updated.textContent = new Date().toLocaleString('de-DE');
}

// Gemeinsame Funktion zum Service-Neustart (bereits in disk2iso_widget definiert)
// Falls nicht vorhanden, hier definieren
if (typeof restartServiceWidget !== 'function') {
    function restartServiceWidget(serviceName) {
        if (!confirm(`Service "${serviceName}" wirklich neu starten?`)) {
            return;
        }
        
        fetch(`/api/widgets/disk2iso-web/restart`, {
            method: 'POST'
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                alert(`Service "${serviceName}" wurde neu gestartet.`);
                setTimeout(() => {
                    loadDisk2IsoServiceWidget();
                    loadDisk2IsoWebServiceWidget();
                }, 2000);
            } else {
                alert(`Fehler beim Neustart: ${data.message}`);
            }
        })
        .catch(error => {
            console.error('Fehler:', error);
            alert('Fehler beim Neustart des Service');
        });
    }
}

// Auto-Update alle 10 Sekunden
if (document.getElementById('disk2iso-web-service-widget')) {
    loadDisk2IsoWebServiceWidget();
    setInterval(loadDisk2IsoWebServiceWidget, 10000);
}
