/**
 * disk2iso v1.2.0 - TMDB Film/TV-Auswahl (BEFORE Copy)
 * Filepath: www/static/js/tmdb-modal.js
 * 
 * Verwaltet die Auswahl bei mehrdeutigen TMDB-Treffern
 * Analog zu musicbrainz.js für Audio-CDs
 */

let currentTmdbResults = [];
let selectedTmdbIndex = 0;
let tmdbCountdownInterval = null;
let tmdbTimeoutRemaining = 0;

/**
 * Prüft ob TMDB Metadata-Auswahl erforderlich ist (BEFORE Copy)
 */
async function checkTmdbStatus() {
    try {
        // Prüfe ob Modal bereits geöffnet ist
        const modal = document.getElementById('tmdb-modal');
        if (modal && modal.style.display === 'flex') {
            // Modal ist bereits offen - nicht neu rendern
            return;
        }
        
        // Prüfe /api/metadata/pending für DVD/Blu-ray
        const response = await fetch('/api/metadata/pending');
        
        if (!response.ok) {
            return;
        }
        
        const data = await response.json();
        
        // Nur für DVD/Blu-ray
        if (data.pending && (data.disc_type === 'dvd-video' || data.disc_type === 'bd-video')) {
            currentTmdbResults = data.results || [];
            selectedTmdbIndex = 0;
            tmdbTimeoutRemaining = data.timeout || 60;
            
            showTmdbModal(data);
        }
    } catch (error) {
        console.error('TMDB Status Check fehlgeschlagen:', error);
    }
}

/**
 * Zeigt das TMDB-Auswahl-Modal
 */
function showTmdbModal(data) {
    const modal = document.getElementById('tmdb-modal');
    const messageEl = document.getElementById('tmdb-message');
    const listEl = document.getElementById('tmdb-results-list');
    
    if (!modal || !listEl) {
        console.error('TMDB Modal-Elemente nicht gefunden');
        return;
    }
    
    // Nachricht aktualisieren
    if (messageEl) {
        const mediaTypeText = data.media_type === 'tv' ? 'TV-Serien' : 'Filme';
        messageEl.textContent = `Mehrere ${mediaTypeText} gefunden. Bitte wählen Sie den richtigen aus:`;
    }
    
    // Liste generieren
    listEl.innerHTML = currentTmdbResults.map((result, index) => {
        const title = result.title || result.name || 'Unbekannter Titel';
        const year = result.release_date?.split('-')[0] || result.first_air_date?.split('-')[0] || '????';
        const overview = result.overview || 'Keine Beschreibung verfügbar';
        const posterUrl = result.poster_path 
            ? `https://image.tmdb.org/t/p/w200${result.poster_path}` 
            : '/static/img/no-poster.png';
        
        return `
            <div class="tmdb-result ${index === 0 ? 'selected' : ''}" data-index="${index}">
                <img src="${posterUrl}" alt="${title}" class="tmdb-poster" onerror="this.src='/static/img/no-poster.png'">
                <div class="tmdb-info">
                    <div class="tmdb-title">${title} (${year})</div>
                    <div class="tmdb-overview">${overview}</div>
                </div>
            </div>
        `;
    }).join('');
    
    // Countdown-Timer und Buttons Container
    const buttonsHTML = `
        <div style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd;">
            <div class="tmdb-countdown" id="tmdb-countdown">
                ⏱️ Noch <span id="tmdb-countdown-seconds">${tmdbTimeoutRemaining}</span> Sekunden...
            </div>
            <div style="display: flex; gap: 10px; justify-content: center; margin-top: 15px;">
                <button onclick="selectTmdbResult()" class="button-primary">Auswählen</button>
                <button onclick="skipTmdbSelection()" class="button-secondary">Metadaten überspringen</button>
            </div>
        </div>
    `;
    
    listEl.insertAdjacentHTML('afterend', buttonsHTML);
    
    // Starte Countdown
    startTmdbCountdown();
    
    // Event-Listener für Klick auf Results
    document.querySelectorAll('.tmdb-result').forEach(el => {
        el.addEventListener('click', function() {
            document.querySelectorAll('.tmdb-result').forEach(r => r.classList.remove('selected'));
            this.classList.add('selected');
            selectedTmdbIndex = parseInt(this.dataset.index);
        });
    });
    
    // Modal anzeigen
    modal.style.display = 'flex';
}

/**
 * Startet den Countdown-Timer
 */
function startTmdbCountdown() {
    // Clear existing countdown
    if (tmdbCountdownInterval) {
        clearInterval(tmdbCountdownInterval);
    }
    
    const secondsEl = document.getElementById('tmdb-countdown-seconds');
    if (!secondsEl) return;
    
    tmdbCountdownInterval = setInterval(() => {
        tmdbTimeoutRemaining--;
        secondsEl.textContent = tmdbTimeoutRemaining;
        
        if (tmdbTimeoutRemaining <= 0) {
            clearInterval(tmdbCountdownInterval);
            skipTmdbSelection(); // Auto-Skip bei Timeout
            return;
        }
        
        // Warnung bei weniger als 10 Sekunden
        if (tmdbTimeoutRemaining <= 10) {
            const countdownDiv = document.getElementById('tmdb-countdown');
            if (countdownDiv) {
                countdownDiv.style.color = '#ff6b6b';
                countdownDiv.style.fontWeight = 'bold';
            }
        }
    }, 1000);
}

/**
 * Wählt das markierte TMDB-Ergebnis aus
 */
async function selectTmdbResult() {
    try {
        // Clear countdown
        if (tmdbCountdownInterval) {
            clearInterval(tmdbCountdownInterval);
        }
        
        // Hole disc_id aus pending-API
        const pendingResponse = await fetch('/api/metadata/pending');
        const pendingData = await pendingResponse.json();
        
        const response = await fetch('/api/metadata/select', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                disc_id: pendingData.disc_id,
                index: selectedTmdbIndex,
                disc_type: pendingData.disc_type
            })
        });
        
        const data = await response.json();
        
        if (data.success) {
            console.log('TMDB Metadata ausgewählt:', selectedTmdbIndex);
            closeTmdbModal();
        } else {
            alert('Fehler bei der Auswahl: ' + data.message);
        }
    } catch (error) {
        console.error('Fehler beim Senden der Auswahl:', error);
        alert('Fehler beim Senden der Auswahl');
    }
}

/**
 * Überspringt die Metadata-Auswahl (Generic Names)
 */
async function skipTmdbSelection() {
    try {
        // Clear countdown
        if (tmdbCountdownInterval) {
            clearInterval(tmdbCountdownInterval);
        }
        
        const pendingResponse = await fetch('/api/metadata/pending');
        const pendingData = await pendingResponse.json();
        
        const response = await fetch('/api/metadata/select', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                disc_id: pendingData.disc_id,
                index: 'skip',
                disc_type: pendingData.disc_type
            })
        });
        
        const data = await response.json();
        
        if (data.success) {
            console.log('TMDB Metadata übersprungen');
            closeTmdbModal();
        } else {
            alert('Fehler beim Überspringen: ' + data.message);
        }
    } catch (error) {
        console.error('Fehler beim Überspringen:', error);
        alert('Fehler beim Überspringen');
    }
}

/**
 * Schließt das TMDB-Modal
 */
function closeTmdbModal() {
    const modal = document.getElementById('tmdb-modal');
    if (modal) {
        modal.style.display = 'none';
    }
    
    // Cleanup
    if (tmdbCountdownInterval) {
        clearInterval(tmdbCountdownInterval);
    }
    currentTmdbResults = [];
    selectedTmdbIndex = 0;
}

// Integration in index.js DOMContentLoaded
if (typeof checkMusicBrainzStatus === 'undefined') {
    // Falls musicbrainz.js nicht geladen ist, starte nur TMDB
    document.addEventListener('DOMContentLoaded', function() {
        checkTmdbStatus();
        setInterval(checkTmdbStatus, 3000); // Alle 3 Sekunden prüfen
    });
}
