/**
 * Softwarecheck Widget (2x1) - Systeminfo
 * Kompakte Übersicht: Alle aktuell ✅ oder Updates verfügbar ⚠️
 * Version: 1.0.0
 */

function loadSoftwareCheckStatus() {
    fetch('/api/widgets/systeminfo/softwarecheck')
        .then(response => response.json())
        .then(data => {
            if (data.success && data.software) {
                updateSoftwareCheckStatus(data.software);
            } else {
                showSoftwareCheckError();
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden des Software-Status:', error);
            showSoftwareCheckError();
        });
}

function updateSoftwareCheckStatus(softwareList) {
    const container = document.getElementById('software-status-container');
    if (!container) return;
    
    // Zähle Status
    let totalCount = softwareList.length;
    let currentCount = 0;
    let outdatedCount = 0;
    let missingCount = 0;
    
    softwareList.forEach(software => {
        const status = software.status || 'unknown';
        const updateAvailable = software.update_available || false;
        
        if (status === 'current') {
            currentCount++;
        } else if (status === 'outdated' || updateAvailable) {
            outdatedCount++;
        } else if (status === 'missing') {
            missingCount++;
        }
    });
    
    // Bestimme Gesamt-Status
    let statusHtml = '';
    
    if (missingCount > 0) {
        // Kritisch: Software fehlt
        statusHtml = `
            <div class="status-critical">
                <div class="status-icon">❌</div>
                <h3 style="margin: 10px 0 5px 0; font-size: 1.1em; color: #c92a2a;">Software fehlt</h3>
                <p style="color: #666; font-size: 0.9em; margin-bottom: 15px;">
                    ${missingCount} von ${totalCount} Tools nicht installiert
                </p>
                <a href="/system" class="btn btn-primary btn-small">
                    Zur Systeminfo →
                </a>
            </div>
        `;
    } else if (outdatedCount > 0) {
        // Warnung: Updates verfügbar
        statusHtml = `
            <div class="status-warning">
                <div class="status-icon">⚠️</div>
                <h3 style="margin: 10px 0 5px 0; font-size: 1.1em; color: #e67700;">Updates verfügbar</h3>
                <p style="color: #666; font-size: 0.9em; margin-bottom: 15px;">
                    ${outdatedCount} von ${totalCount} Tools veraltet
                </p>
                <a href="/system" class="btn btn-update btn-small">
                    Updates anzeigen →
                </a>
            </div>
        `;
    } else {
        // Alles OK
        statusHtml = `
            <div class="status-ok">
                <div class="status-icon">✅</div>
                <h3 style="margin: 10px 0 5px 0; font-size: 1.1em; color: #2b8a3e;">Alles aktuell</h3>
                <p style="color: #666; font-size: 0.9em; margin-bottom: 15px;">
                    Alle ${totalCount} Tools auf dem neuesten Stand
                </p>
                <a href="/system" class="btn btn-secondary btn-small" style="opacity: 0.7;">
                    Details anzeigen →
                </a>
            </div>
        `;
    }
    
    container.innerHTML = statusHtml;
}

function showSoftwareCheckError() {
    const container = document.getElementById('software-status-container');
    if (!container) return;
    
    container.innerHTML = `
        <div class="status-error">
            <div class="status-icon">❓</div>
            <h3 style="margin: 10px 0 5px 0; font-size: 1.1em; color: #868e96;">Status unbekannt</h3>
            <p style="color: #666; font-size: 0.9em; margin-bottom: 15px;">
                Fehler beim Laden der Software-Informationen
            </p>
            <a href="/system" class="btn btn-secondary btn-small">
                Zur Systeminfo →
            </a>
        </div>
    `;
}

// Auto-Load + Auto-Update (alle 5 Minuten)
if (document.getElementById('systeminfo-softwarecheck-widget')) {
    loadSoftwareCheckStatus();
    
    // Aktualisiere alle 5 Minuten
    setInterval(loadSoftwareCheckStatus, 300000);
}
