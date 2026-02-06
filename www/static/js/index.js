/**
 * disk2iso - Home Page JavaScript
 * Version: 1.2.0
 * 
 * Note: Live Status Logic wurde ins livestatus_6x6_systeminfo.js Widget verschoben
 */

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', function() {
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
