/**
 * Widget: livestatus_6x6_systeminfo - Live Status Dashboard
 * Zeigt Echtzeit-Status des disk2iso Service mit Kopierfortschritt
 * Version: 1.2.0
 */

(function() {
    let updateInterval = null;

    /**
     * Aktualisiert Live Status Anzeige
     */
    function updateLiveStatus() {
        fetch('/api/status')
            .then(response => response.json())
            .then(data => {
                const live = data.live_status;
                const statusIndicator = document.getElementById('live-status-indicator');
                const statusLabel = document.getElementById('live-status-label');
                const discMediumRow = document.getElementById('disc-medium-row');
                const discMedium = document.getElementById('disc-medium');
                const discModeRow = document.getElementById('disc-mode-row');
                const discMode = document.getElementById('disc-mode');
                
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
                
                // Live Status für globalen Zugriff speichern (für Service Restart Warning)
                window.liveStatus = live;
            })
            .catch(error => {
                console.error('Fehler beim Laden der Live-Daten:', error);
            });
    }

    // Widget-Initialisierung
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initWidget);
    } else {
        initWidget();
    }

    function initWidget() {
        // Initialer Aufruf
        updateLiveStatus();
        
        // Alle 5 Sekunden aktualisieren
        updateInterval = setInterval(updateLiveStatus, 5000);
    }

    // Export für eventuellen manuellen Stop
    window.liveStatusWidget = {
        stop: function() {
            if (updateInterval) {
                clearInterval(updateInterval);
                updateInterval = null;
            }
        },
        start: function() {
            if (!updateInterval) {
                updateLiveStatus();
                updateInterval = setInterval(updateLiveStatus, 5000);
            }
        }
    };
})();
