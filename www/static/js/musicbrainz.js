/**
 * disk2iso v1.2.0 - MusicBrainz Album-Auswahl
 * Filepath: www/static/js/musicbrainz.js
 * 
 * Verwaltet die Auswahl bei mehrdeutigen MusicBrainz-Treffern
 * BEFORE Copy Strategy: Modal erscheint VOR dem Ripping
 */

let currentReleases = [];
let selectedIndex = 0;
let mbCheckInterval = null;
let countdownInterval = null;
let timeoutRemaining = 0;

/**
 * Prüft ob Metadata-Auswahl erforderlich ist (BEFORE Copy)
 */
async function checkMusicBrainzStatus() {
    try {
        // Prüfe ob Modal bereits geöffnet ist
        const modal = document.getElementById('musicbrainz-modal');
        if (modal && modal.style.display === 'flex') {
            // Modal ist bereits offen - nicht neu rendern um Benutzerauswahl zu erhalten
            return;
        }
        
        // Neuer Endpoint: /api/metadata/pending
        const response = await fetch('/api/metadata/pending');
        
        if (!response.ok) {
            return;
        }
        
        const data = await response.json();
        
        if (data.pending && data.disc_type === 'audio-cd') {
            currentReleases = data.releases || [];
            selectedIndex = 0;
            timeoutRemaining = data.timeout || 60;
            
            showMusicBrainzModal(data);
        }
    } catch (error) {
        console.error('Metadata Status Check fehlgeschlagen:', error);
    }
}

/**
 * Zeigt das MusicBrainz-Auswahl-Modal
 */
function showMusicBrainzModal(data) {
    const modal = document.getElementById('musicbrainz-modal');
    const messageEl = document.getElementById('mb-message');
    const listEl = document.getElementById('mb-releases-list');
    
    if (!modal || !listEl) return;
    
    // Nachricht aktualisieren
    if (messageEl) {
        messageEl.textContent = data.message || 'Mehrere Alben gefunden. Bitte wählen Sie das richtige Album aus:';
    }
    
    // Release-Liste aufbauen
    listEl.innerHTML = '';
    
    currentReleases.forEach((release, index) => {
        const releaseDiv = document.createElement('div');
        releaseDiv.className = 'release-item';
        if (index === selectedIndex) {
            releaseDiv.classList.add('selected');
        }
        
        // Berechne Laufzeit in MM:SS Format
        let durationStr = '';
        if (release.duration) {
            const totalSeconds = Math.floor(release.duration / 1000);
            const hours = Math.floor(totalSeconds / 3600);
            const minutes = Math.floor((totalSeconds % 3600) / 60);
            const seconds = totalSeconds % 60;
            if (hours > 0) {
                durationStr = `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
            } else {
                durationStr = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
            }
        }
        
        // Verwende lokalen Cover-Endpoint (wird in .temp gecacht)
        const coverUrl = release.id ? `/api/musicbrainz/cover/${release.id}` : null;
        
        releaseDiv.innerHTML = `
            <input type="radio" 
                   name="release" 
                   id="release-${index}" 
                   value="${index}" 
                   ${index === selectedIndex ? 'checked' : ''}>
            <label for="release-${index}">
                <div class="release-layout">
                    ${coverUrl ? `<img src="${coverUrl}" alt="Cover" class="release-cover" onerror="this.style.display='none'">` : '<div class="release-cover-placeholder"></div>'}
                    <div class="release-info">
                        <div class="release-title">${escapeHtml(release.title || 'Unknown')}</div>
                        <div class="release-artist">${escapeHtml(release.artist || 'Unknown Artist')}</div>
                        <div class="release-details">
                            ${release.date && release.date !== 'unknown' ? `<span class="release-date">${release.date}</span>` : ''}
                            ${release.country && release.country !== 'unknown' ? `<span class="release-country">${release.country}</span>` : ''}
                            ${release.label && release.label !== 'Unknown' ? `<span class="release-label">${escapeHtml(release.label)}</span>` : ''}
                        </div>
                        <div class="release-stats">
                            <span class="release-tracks">${release.tracks || 0} Tracks</span>
                            ${durationStr ? `<span class="release-duration">${durationStr}</span>` : ''}
                        </div>
                    </div>
                </div>
            </label>
        `;
        
        releaseDiv.querySelector('input').addEventListener('change', () => {
            selectedIndex = index;
            document.querySelectorAll('.release-item').forEach(el => el.classList.remove('selected'));
            releaseDiv.classList.add('selected');
        });
        
        listEl.appendChild(releaseDiv);
    });
    
    // Countdown-Timer und Buttons Container
    const buttonsDiv = document.createElement('div');
    buttonsDiv.className = 'mb-buttons-container';
    buttonsDiv.innerHTML = `
        <div class="mb-countdown" id="mb-countdown">
            ⏱️ Noch <span id="mb-countdown-seconds">${timeoutRemaining}</span> Sekunden...
        </div>
        <div class="mb-buttons">
            <button class="btn btn-secondary" onclick="skipMusicBrainzSelection()">Überspringen</button>
            <button class="btn btn-primary" onclick="confirmMusicBrainzSelection()">Album bestätigen</button>
        </div>
    `;
    
    listEl.appendChild(buttonsDiv);
    
    // Modal anzeigen
    modal.style.display = 'flex';
    
    // Starte Countdown
    startCountdown();
}

/**
 * Startet den Countdown-Timer
 */
function startCountdown() {
    // Clear existing countdown
    if (countdownInterval) {
        clearInterval(countdownInterval);
    }
    
    const secondsEl = document.getElementById('mb-countdown-seconds');
    if (!secondsEl) return;
    
    countdownInterval = setInterval(() => {
        timeoutRemaining--;
        
        if (timeoutRemaining <= 0) {
            clearInterval(countdownInterval);
            // Auto-Skip bei Timeout
            skipMusicBrainzSelection();
        } else {
            secondsEl.textContent = timeoutRemaining;
            
            // Warnung bei wenig Zeit
            const countdownDiv = document.getElementById('mb-countdown');
            if (timeoutRemaining <= 10 && countdownDiv) {
                countdownDiv.style.color = '#ff6b6b';
                countdownDiv.style.fontWeight = 'bold';
            }
        }
    }, 1000);
}

/**
 * Schließt das MusicBrainz-Modal
 */
function closeMusicBrainzModal() {
    const modal = document.getElementById('musicbrainz-modal');
    if (modal) {
        modal.style.display = 'none';
    }
    
    // Clear countdown
    if (countdownInterval) {
        clearInterval(countdownInterval);
        countdownInterval = null;
    }
    
    // Starte Interval-Prüfung wieder (falls gestoppt)
    if (!mbCheckInterval) {
        mbCheckInterval = setInterval(checkMusicBrainzStatus, 5000);
    }
}

/**
 * Überspringt die Metadata-Auswahl (generische Namen)
 */
async function skipMusicBrainzSelection() {
    try {
        // Lese disc_id aus pending-data
        const pendingResponse = await fetch('/api/metadata/pending');
        const pendingData = await pendingResponse.json();
        
        const response = await fetch('/api/metadata/select', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                disc_id: pendingData.disc_id,
                index: 'skip',
                disc_type: 'audio-cd'
            })
        });
        
        if (response.ok) {
            closeMusicBrainzModal();
            showNotification('Metadaten übersprungen - verwende generische Namen', 'info');
        } else {
            throw new Error('Skip fehlgeschlagen');
        }
    } catch (error) {
        console.error('Skip Metadata fehlgeschlagen:', error);
        showNotification('Fehler beim Überspringen', 'error');
    }
}

/**
 * Bestätigt die ausgewählte MusicBrainz-Release (BEFORE Copy)
 */
async function confirmMusicBrainzSelection() {
    try {
        // Lese disc_id aus pending-data
        const pendingResponse = await fetch('/api/metadata/pending');
        const pendingData = await pendingResponse.json();
        
        const response = await fetch('/api/metadata/select', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ index: selectedIndex })
        });
        
        const result = await response.json();
        
        if (result.success) {
            closeMusicBrainzModal();
            
            // Zeige Bestätigung
            showNotification('Album ausgewählt. Kopiervorgang wird fortgesetzt...', 'success');
            
            // Aktualisiere Status nach 2 Sekunden
            setTimeout(() => {
                if (typeof updateStatus === 'function') {
                    updateStatus();
                }
            }, 2000);
        } else {
            showNotification('Fehler beim Speichern: ' + result.message, 'error');
        }
    } catch (error) {
        console.error('Fehler beim Bestätigen:', error);
        showNotification('Fehler beim Bestätigen der Auswahl', 'error');
    }
}

/**
 * Sendet manuelle Metadaten
 */
async function submitManualMetadata() {
    const artist = document.getElementById('manual-artist').value.trim();
    const album = document.getElementById('manual-album').value.trim();
    const year = document.getElementById('manual-year').value.trim();
    
    if (!artist || !album || !year) {
        showNotification('Bitte füllen Sie alle Felder aus', 'warning');
        return;
    }
    
    try {
        const response = await fetch('/api/musicbrainz/manual', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ artist, album, year })
        });
        
        const result = await response.json();
        
        if (result.success) {
            closeMusicBrainzModal();
            showNotification('Metadaten gespeichert. Kopiervorgang wird fortgesetzt...', 'success');
            
            setTimeout(() => {
                if (typeof updateStatus === 'function') {
                    updateStatus();
                }
            }, 2000);
        } else {
            showNotification('Fehler beim Speichern: ' + result.message, 'error');
        }
    } catch (error) {
        console.error('Fehler beim Speichern:', error);
        showNotification('Fehler beim Speichern der Metadaten', 'error');
    }
}

/**
 * HTML-Escaping
 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

/**
 * Zeigt eine Benachrichtigung
 */
function showNotification(message, type = 'info') {
    // Einfache Benachrichtigung (kann später durch Toast ersetzt werden)
    const notification = document.createElement('div');
    notification.className = `notification notification-${type}`;
    notification.textContent = message;
    notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 15px 20px;
        background: ${type === 'success' ? '#27ae60' : type === 'error' ? '#e74c3c' : '#3498db'};
        color: white;
        border-radius: 4px;
        z-index: 10000;
        box-shadow: 0 2px 10px rgba(0,0,0,0.3);
    `;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.style.opacity = '0';
        notification.style.transition = 'opacity 0.3s';
        setTimeout(() => notification.remove(), 300);
    }, 3000);
}

// Prüfe alle 5 Sekunden ob MusicBrainz-Auswahl erforderlich ist
// Nur wenn Modal existiert (d.h. auf Archive-Seite)
if (document.getElementById('musicbrainz-modal')) {
    mbCheckInterval = setInterval(checkMusicBrainzStatus, 5000);
    
    // Initiale Prüfung beim Laden
    document.addEventListener('DOMContentLoaded', () => {
        setTimeout(checkMusicBrainzStatus, 1000);
    });
}
