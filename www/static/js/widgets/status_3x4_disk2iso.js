/**
 * Status Widget (2x1) - Disk2iso
 * Lädt dynamisch den Status des disk2iso Service
 * Version: 1.0.0
 */

function loadDisk2IsoServiceWidget() {
    fetch('/api/widgets/disk2iso/status')
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                updateDisk2IsoServiceWidget(data);
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden des disk2iso Service Status:', error);
        });
}

function updateDisk2IsoServiceWidget(data) {
    const indicator = document.getElementById('disk2iso-widget-indicator');
    const status = document.getElementById('disk2iso-widget-status');
    const badge = document.getElementById('disk2iso-widget-badge');
    const updated = document.getElementById('disk2iso-widget-updated');
    
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

function restartServiceWidget(serviceName) {
    if (!confirm(`Service "${serviceName}" wirklich neu starten?`)) {
        return;
    }
    
    fetch(`/api/widgets/disk2iso/restart`, {
        method: 'POST'
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            alert(`Service "${serviceName}" wurde neu gestartet.`);
            setTimeout(() => loadDisk2IsoServiceWidget(), 2000);
        } else {
            alert(`Fehler beim Neustart: ${data.message}`);
        }
    })
    .catch(error => {
        console.error('Fehler:', error);
        alert('Fehler beim Neustart des Service');
    });
}

// Auto-Update alle 10 Sekunden
if (document.getElementById('disk2iso-service-widget')) {
    loadDisk2IsoServiceWidget();
    setInterval(loadDisk2IsoServiceWidget, 10000);
}
