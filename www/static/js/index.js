/**
 * disk2iso - Home Page JavaScript
 */

let updateInterval = null;

function updateLiveStatus() {
    fetch('/api/status')
        .then(response => response.json())
        .then(data => {
            // Service Status aktualisieren
            const serviceIndicator = document.querySelector('.status-indicator');
            const serviceText = serviceIndicator.nextSibling.nextSibling;
            if (data.service_running) {
                serviceIndicator.className = 'status-indicator running';
                serviceText.textContent = 'Running';
            } else {
                serviceIndicator.className = 'status-indicator stopped';
                serviceText.textContent = 'Stopped';
            }
            
            // ISO Count aktualisieren
            const isoCountElements = document.querySelectorAll('.info-value');
            isoCountElements.forEach(el => {
                if (el.previousElementSibling && el.previousElementSibling.textContent === 'Anzahl ISOs') {
                    el.textContent = data.iso_count;
                }
            });
            
            // Live Status
            const live = data.live_status;
            const statusIndicator = document.getElementById('live-status-indicator');
            const statusLabel = document.getElementById('live-status-label');
            const discInfoRow = document.getElementById('disc-info-row');
            const discInfo = document.getElementById('disc-info');
            const progressSection = document.getElementById('progress-section');
            
            // Prüfe ob Service läuft
            const serviceRunning = data.service_running;
            
            // Intelligente Status-Erkennung
            let statusText = 'Unbekannt';
            let statusClass = 'stopped';
            
            if (!serviceRunning) {
                // Service läuft nicht
                statusText = 'Service gestoppt';
                statusClass = 'stopped';
            } else if (live.status === 'idle') {
                // Service läuft, aber idle
                // Prüfe ob jemals ein Laufwerk erkannt wurde (anhand von method oder disc_type)
                if (!live.method || live.method === 'unknown') {
                    statusText = 'Kein Laufwerk erkannt';
                    statusClass = 'stopped';
                } else {
                    statusText = 'Wartet auf Medium';
                    statusClass = 'stopped';
                }
            } else if (live.status === 'waiting') {
                statusText = 'Medium wird geprüft...';
                statusClass = 'stopped';
            } else if (live.status === 'copying') {
                statusText = 'Kopiert Medium';
                statusClass = 'copying';
            } else if (live.status === 'completed') {
                statusText = 'Abgeschlossen';
                statusClass = 'running';
            } else if (live.status === 'error') {
                statusText = 'Fehler aufgetreten';
                statusClass = 'stopped';
            }
            
            statusLabel.textContent = statusText;
            statusIndicator.className = 'status-indicator ' + statusClass;
            
            // Disc-Info anzeigen wenn verfügbar
            if (live.disc_label || live.disc_type) {
                discInfoRow.style.display = '';
                discInfo.textContent = `${live.disc_label || 'Unbekannt'} (${live.disc_type || '-'})`;
            } else {
                discInfoRow.style.display = 'none';
            }
            
            // Fortschritt anzeigen wenn kopiert wird
            if (live.status === 'copying' && live.progress_percent > 0) {
                progressSection.style.display = '';
                document.getElementById('progress-percent').textContent = live.progress_percent;
                document.getElementById('progress-mb').textContent = live.progress_mb;
                document.getElementById('total-mb').textContent = live.total_mb;
                document.getElementById('eta-text').textContent = live.eta || '-';
                
                // Einheit basierend auf Disc-Typ setzen
                const progressUnit = document.getElementById('progress-unit');
                if (live.disc_type === 'audio-cd') {
                    progressUnit.textContent = 'Tracks';
                } else {
                    progressUnit.textContent = 'MB';
                }
                
                const progressBar = document.getElementById('progress-bar-fill');
                const progressBarContainer = progressBar.parentElement;
                progressBar.style.width = live.progress_percent + '%';
                progressBarContainer.setAttribute('data-label', live.progress_percent + '%');
            } else {
                progressSection.style.display = 'none';
            }
            
            // Timestamp aktualisieren
            const updateElement = document.querySelector('.info-row:has(.info-label:contains("Aktualisiert")) .info-value');
            if (updateElement) {
                updateElement.textContent = new Date().toLocaleString('de-DE');
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden der Live-Daten:', error);
        });
}

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', function() {
    // Initialer Aufruf
    updateLiveStatus();
    
    // Alle 5 Sekunden aktualisieren
    updateInterval = setInterval(updateLiveStatus, 5000);
});
