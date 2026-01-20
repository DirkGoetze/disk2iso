/**
 * disk2iso - Home Page JavaScript
 * Version: 1.2.0
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
            const discMediumRow = document.getElementById('disc-medium-row');
            const discMedium = document.getElementById('disc-medium');
            const discModeRow = document.getElementById('disc-mode-row');
            const discMode = document.getElementById('disc-mode');
            const progressSection = document.getElementById('progress-section');
            
            // Prüfe ob Service läuft
            const serviceRunning = data.service_running;
            
            // Intelligente Status-Erkennung
            let statusText = window.i18n?.STATUS_UNKNOWN || 'Unknown';
            let statusClass = 'stopped';
            
            if (!serviceRunning) {
                // Service läuft nicht
                statusText = window.i18n?.STATUS_SERVICE_STOPPED || 'Service stopped';
                statusClass = 'stopped';
            } else if (live.status === 'idle') {
                // Service läuft, aber idle
                // Prüfe ob jemals ein Laufwerk erkannt wurde (anhand von method oder disc_type)
                if (!live.method || live.method === 'unknown') {
                    statusText = window.i18n?.STATUS_NO_DRIVE || 'No drive detected';
                    statusClass = 'stopped';
                } else {
                    statusText = window.i18n?.STATUS_WAITING_MEDIA || 'Waiting for media...';
                    statusClass = 'stopped';
                }
            } else if (live.status === 'waiting') {
                statusText = window.i18n?.STATUS_ANALYZING || 'Analyzing media...';
                statusClass = 'stopped';
            } else if (live.status === 'waiting_for_metadata') {
                statusText = window.i18n?.STATUS_WAITING_FOR_METADATA || 'Waiting for metadata selection...';
                statusClass = 'stopped';
            } else if (live.status === 'copying') {
                statusText = window.i18n?.STATUS_COPYING || 'Copying...';
                statusClass = 'copying';
            } else if (live.status === 'completed') {
                statusText = window.i18n?.STATUS_COMPLETED || 'Completed';
                statusClass = 'running';
            } else if (live.status === 'error') {
                statusText = window.i18n?.STATUS_ERROR || 'Error occurred';
                statusClass = 'stopped';
            }
            
            statusLabel.textContent = statusText;
            statusIndicator.className = 'status-indicator ' + statusClass;
            
            // Medium anzeigen (ISO-Dateiname)
            if (live.disc_label) {
                discMediumRow.classList.remove('inactive');
                discMedium.textContent = live.disc_label;
            } else {
                discMediumRow.classList.add('inactive');
                discMedium.textContent = '-';
            }
            
            // Modus anzeigen (Disc-Typ + Methode)
            if (live.disc_type && live.disc_type !== '-' && live.disc_type !== '') {
                discModeRow.classList.remove('inactive');
                const method = live.method && live.method !== 'unknown' ? ` (${live.method})` : '';
                discMode.textContent = `${live.disc_type}${method}`;
            } else {
                discModeRow.classList.add('inactive');
                discMode.textContent = '-';
            }
            
            // Fortschritt anzeigen wenn kopiert wird
            const progressRow = document.getElementById('progress-row');
            const progressBarContainer = document.getElementById('progress-bar');
            const etaRow = document.getElementById('eta-row');
            
            if (live.status === 'copying' && live.progress_percent > 0) {
                progressRow.classList.remove('inactive');
                progressBarContainer.classList.remove('inactive');
                etaRow.classList.remove('inactive');
                
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
                
                // Overlay zeigt verbleibenden Teil (100 - Fortschritt)
                const progressOverlay = progressBarContainer.querySelector('.progress-overlay-copying');
                const remainingPercent = 100 - live.progress_percent;
                progressOverlay.style.width = remainingPercent + '%';
                progressBarContainer.setAttribute('data-label', live.progress_percent + '%');
            } else {
                progressRow.classList.add('inactive');
                progressBarContainer.classList.add('inactive');
                etaRow.classList.add('inactive');
                
                document.getElementById('progress-percent').textContent = '0';
                document.getElementById('progress-mb').textContent = '0';
                document.getElementById('total-mb').textContent = '0';
                document.getElementById('eta-text').textContent = '-';
                
                // Overlay auf 100% (alles grau)
                const progressOverlay = progressBarContainer.querySelector('.progress-overlay-copying');
                if (progressOverlay) {
                    progressOverlay.style.width = '100%';
                }
                progressBarContainer.setAttribute('data-label', '0%');
            }
            
            // Archive-Counts aktualisieren
            if (data.archive_counts) {
                const archiveLabels = {
                    'Daten-Discs': 'data',
                    'Audio CDs': 'audio',
                    'DVDs': 'dvd',
                    'Blu-rays': 'bluray'
                };
                
                document.querySelectorAll('.info-row').forEach(row => {
                    const label = row.querySelector('.info-label');
                    const value = row.querySelector('.info-value');
                    if (label && value) {
                        const labelText = label.textContent.trim();
                        if (archiveLabels[labelText]) {
                            value.textContent = data.archive_counts[archiveLabels[labelText]];
                        }
                    }
                });
            }
            
            // Timestamp aktualisieren - keine automatische Aktualisierung mehr nötig
            // (wird vom Server bei jedem Reload gesetzt)
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
    
    // MusicBrainz/TMDB Metadata-Auswahl prüfen (für BEFORE Copy Strategy)
    if (typeof checkMusicBrainzStatus === 'function') {
        checkMusicBrainzStatus();
        setInterval(checkMusicBrainzStatus, 3000); // Alle 3 Sekunden prüfen
    }
});

/**
 * Startet einen Service von der Home-Seite neu
 */
function restartServiceHome(serviceName) {
    // Prüfe ob gerade ein Kopiervorgang läuft
    if (window.liveStatus && (window.liveStatus.status === 'copying' || window.liveStatus.status === 'analyzing')) {
        const confirmMsg = `⚠️ ACHTUNG!\n\nEin Kopiervorgang läuft gerade!\n\nWenn Sie den Service jetzt neu starten, gehen alle Daten des laufenden Kopiervorgangs verloren.\n\nMöchten Sie trotzdem fortfahren?`;
        
        if (!confirm(confirmMsg)) {
            return;
        }
    } else {
        if (!confirm(`Service "${serviceName}" wirklich neu starten?`)) {
            return;
        }
    }
    
    fetch('/api/service/restart', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ service: serviceName })
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            alert(`✅ ${data.message}`);
            // Aktualisiere Status sofort
            window.location.reload();
        } else {
            alert(`❌ Fehler: ${data.message}`);
        }
    })
    .catch(error => {
        console.error('Fehler:', error);
        alert(`❌ Fehler beim Neustart: ${error}`);
    });
}
