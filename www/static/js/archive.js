/**
 * disk2iso - Archive Page JavaScript
 * Version: 1.2.0
 */

function formatBytes(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}

function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleString('de-DE', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit'
    });
}

function createFileItem(file) {
    const card = document.createElement('div');
    card.className = 'archive-card col-2';
    
    // Prüfe ob Metadaten fehlen (Disc_* Pattern oder keine .nfo)
    const needsMetadata = file.name.startsWith('Disc_') || file.name.startsWith('disc_') || !file.metadata;
    const isAudioCD = file.path.includes('/audio/');
    const isDVDorBD = file.path.includes('/dvd/') || file.path.includes('/bd/');
    
    // Bestimme Typ für Placeholder
    let mediaType = 'data';
    if (isAudioCD) mediaType = 'audio';
    else if (file.path.includes('/dvd/')) mediaType = 'dvd';
    else if (file.path.includes('/bd/')) mediaType = 'bluray';
    
    // Cover Section
    let coverHTML = '';
    if (file.metadata && file.thumbnail) {
        const thumbUrl = `/api/archive/thumbnail/${file.thumbnail}`;
        coverHTML = `<img src="${thumbUrl}" alt="Cover" onerror="this.style.display='none'; this.parentElement.innerHTML=getPlaceholderSVG('${mediaType}');">`;
    } else {
        coverHTML = getPlaceholderSVG(mediaType);
    }
    
    // Metadata extraction
    let title = file.name;
    let artist = '';
    let year = '';
    let tracks = '';
    let duration = '';
    let genre = '';
    let rating = '';
    
    if (file.metadata) {
        const meta = file.metadata;
        title = meta.title || file.name;
        
        if (meta.type === 'audio-cd') {
            artist = meta.artist || 'Unknown Artist';
            year = meta.date || meta.year || '';
            tracks = meta.tracks || '';
            duration = meta.duration || '';
        } else if (meta.type === 'dvd-video' || meta.type === 'bd-video') {
            // Extrahiere Season/Disc Info
            const filename = file.name.toLowerCase().replace('.iso', '');
            const seasonMatch = filename.match(/season[_\s]*(\d+)/i);
            const discMatch = filename.match(/dis[ck][_\s]*(\d+)/i);
            
            if (seasonMatch || discMatch) {
                let parts = [];
                if (seasonMatch) parts.push(`Season ${seasonMatch[1]}`);
                if (discMatch) parts.push(`Disc ${discMatch[1]}`);
                artist = parts.join(' • ');
            } else {
                artist = meta.director || 'Unknown Director';
            }
            
            year = meta.year || '';
            genre = meta.genre || '';
            rating = meta.rating || '';
            duration = meta.runtime ? `${meta.runtime} Min.` : '';
        }
    }
    
    // Build card HTML
    card.innerHTML = `
        <div class="archive-card-cover">
            ${coverHTML}
        </div>
        <div class="archive-card-content">
            <h4 class="archive-card-title">${escapeHtml(title)}</h4>
            ${artist ? `<p class="archive-card-artist">${escapeHtml(artist)}</p>` : ''}
            <div class="archive-card-meta">
                ${year ? `<span><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M9 11H7v2h2v-2zm4 0h-2v2h2v-2zm4 0h-2v2h2v-2zm2-7h-1V2h-2v2H8V2H6v2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 16H5V9h14v11z"/></svg>${escapeHtml(year)}</span>` : ''}
                ${tracks ? `<span><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>${escapeHtml(tracks)} Tracks</span>` : ''}
                ${duration ? `<span><svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 6v6l4 2"/></svg>${escapeHtml(duration)}</span>` : ''}
                ${genre ? `<span>${escapeHtml(genre)}</span>` : ''}
                ${rating ? `<span>⭐ ${escapeHtml(rating)}/10</span>` : ''}
            </div>
        </div>
        <div class="archive-card-technical">
            <span>💾 ${formatBytes(file.size)}</span>
            <span>📅 ${formatDate(file.modified)}</span>
        </div>
        <div class="archive-card-actions">
            <button class="btn-edit" onclick="openMetadataModal('${file.path}', '${mediaType}')">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/>
                </svg>
                Metadaten
            </button>
            <button class="btn-search" onclick="searchMetadataForFile('${file.path}', '${mediaType}')">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/>
                </svg>
                Suchen
            </button>
            <button class="btn-download" onclick="downloadISO('${file.path}')">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/>
                </svg>
                Download
            </button>
        </div>
    `;
    
    return card;
}

// Helper function to generate SVG placeholders
function getPlaceholderSVG(type) {
    const svgs = {
        'audio': `<svg width="120" height="120" viewBox="0 0 24 24" fill="#9ca3af">
            <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>
        </svg>`,
        'dvd': `<svg width="120" height="120" viewBox="0 0 24 24" fill="#9ca3af">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-12.5c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zm0 5.5c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
        </svg>`,
        'bluray': `<svg width="120" height="120" viewBox="0 0 24 24" fill="#9ca3af">
            <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm0-12.5c-2.49 0-4.5 2.01-4.5 4.5s2.01 4.5 4.5 4.5 4.5-2.01 4.5-4.5-2.01-4.5-4.5-4.5zm0 5.5c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
        </svg>`,
        'data': `<svg width="120" height="120" viewBox="0 0 24 24" fill="#9ca3af">
            <path d="M6 2c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6H6zm7 7V3.5L18.5 9H13z"/>
        </svg>`
    };
    return svgs[type] || svgs['data'];
}

function loadArchive() {
    fetch('/api/archive')
        .then(response => response.json())
        .then(data => {
            // Update counts
            document.getElementById('total-count').textContent = data.total;
            document.getElementById('audio-count').textContent = data.by_type.audio.length;
            document.getElementById('dvd-count').textContent = data.by_type.dvd.length;
            document.getElementById('bluray-count').textContent = data.by_type.bluray.length;
            document.getElementById('data-count').textContent = data.by_type.data.length;

            // Populate Audio section
            const audioSection = document.getElementById('audio-section');
            const audioList = document.getElementById('audio-list');
            if (data.by_type.audio.length > 0) {
                audioSection.style.display = 'block';
                audioList.innerHTML = '';
                data.by_type.audio.forEach(file => {
                    audioList.appendChild(createFileItem(file));
                });
            } else {
                audioSection.style.display = 'none';
            }

            // Populate DVD section
            const dvdSection = document.getElementById('dvd-section');
            const dvdList = document.getElementById('dvd-list');
            if (data.by_type.dvd.length > 0) {
                dvdSection.style.display = 'block';
                dvdList.innerHTML = '';
                data.by_type.dvd.forEach(file => {
                    dvdList.appendChild(createFileItem(file));
                });
            } else {
                dvdSection.style.display = 'none';
            }

            // Populate Blu-ray section
            const bluraySection = document.getElementById('bluray-section');
            const blurayList = document.getElementById('bluray-list');
            if (data.by_type.bluray.length > 0) {
                bluraySection.style.display = 'block';
                blurayList.innerHTML = '';
                data.by_type.bluray.forEach(file => {
                    blurayList.appendChild(createFileItem(file));
                });
            } else {
                bluraySection.style.display = 'none';
            }

            // Populate Data section
            const dataSection = document.getElementById('data-section');
            const dataList = document.getElementById('data-list');
            if (data.by_type.data.length > 0) {
                dataSection.style.display = 'block';
                dataList.innerHTML = '';
                data.by_type.data.forEach(file => {
                    dataList.appendChild(createFileItem(file));
                });
            } else {
                dataSection.style.display = 'none';
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden des Archivs:', error);
            ['audio', 'dvd', 'bluray', 'data'].forEach(type => {
                const list = document.getElementById(`${type}-list`);
                if (list) {
                    list.innerHTML = '<p class="error">Fehler beim Laden der Daten</p>';
                }
            });
        });
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// =============================================================================
// RETROACTIVE METADATA MODAL
// =============================================================================

let currentMetadataPath = '';
let currentMetadataType = '';

// Extrahiere Titel aus ISO-Dateiname (entspricht extract_movie_title() aus Bash)
function extractTitleFromFilename(filename) {
    // Entferne Pfad und .iso Extension
    let title = filename.split('/').pop().replace(/\.iso$/, '');
    
    // Entferne gängige Suffixe
    title = title.replace(/_disc_?\d+$/i, '');
    title = title.replace(/_dvd$/i, '');
    title = title.replace(/_bluray$/i, '');
    title = title.replace(/_bd$/i, '');
    
    // Entferne Season/Staffel-Informationen (für TV-Serien)
    title = title.replace(/_season[_\s]*\d+/i, '');
    title = title.replace(/_s\d{2}/i, '');  // S01, S02, etc.
    
    // Entferne Jahr am Ende (4-stellig)
    title = title.replace(/_\d{4}$/, '');
    
    // Ersetze Unterstriche und Bindestriche durch Leerzeichen
    title = title.replace(/[_-]/g, ' ');
    
    // Kapitalisierung (erster Buchstabe jedes Wortes)
    title = title.replace(/\b\w/g, l => l.toUpperCase());
    
    return title.trim();
}

// Erkenne ob es eine TV-Serie ist (Season im Dateinamen)
function detectMediaType(filename) {
    const lowerName = filename.toLowerCase();
    if (lowerName.match(/season[_\s]*\d+/) || lowerName.match(/s\d{2}e\d{2}/)) {
        return 'tv';
    }
    return 'movie';
}

function openMetadataModal(isoPath, type) {
    currentMetadataPath = isoPath;
    currentMetadataType = type;
    
    const modal = document.getElementById('metadata-modal');
    const searchType = document.getElementById('metadata-search-type');
    const searchFields = document.getElementById('metadata-search-fields');
    const resultsDiv = document.getElementById('metadata-results');
    
    // Stoppe altes TMDB-Polling falls aktiv
    if (typeof stopTmdbResultCheck === 'function') {
        stopTmdbResultCheck();
    }
    
    if (type === 'audio') {
        searchType.textContent = 'MusicBrainz-Suche';
        
        // Zeige Suchen-Button für Audio
        const searchButton = document.getElementById('metadata-search-button');
        if (searchButton) {
            searchButton.style.display = 'block';
        }
        
        // Prüfe ob .mbquery existiert (zeige Hinweis)
        const isoBase = isoPath.replace(/\.iso$/, '');
        const mbqueryPath = isoBase + '.mbquery';
        
        searchFields.innerHTML = `
            <div class="info-message" style="background: #e8f4f8; padding: 10px; border-radius: 4px; margin-bottom: 10px; display: none;" id="mbquery-hint">
                ℹ️ Diese CD hatte mehrere Treffer beim Rippen. Die Suche nutzt die gespeicherten Daten für exakte Ergebnisse.
            </div>
            <input type="text" id="search-artist" placeholder="Künstler (optional bei gespeicherten Daten)" class="form-control">
            <input type="text" id="search-album" placeholder="Album (optional bei gespeicherten Daten)" class="form-control">
        `;
        resultsDiv.innerHTML = '';
    } else {
        // TMDB-Suche: Automatischer Workflow
        searchType.textContent = 'TMDB-Suche';
        
        // Verstecke globalen Suchen-Button für TMDB
        const searchButton = document.getElementById('metadata-search-button');
        if (searchButton) {
            searchButton.style.display = 'none';
        }
        
        // Extrahiere Titel aus Dateinamen
        const extractedTitle = extractTitleFromFilename(isoPath);
        const mediaType = detectMediaType(isoPath);
        
        // Zeige Lade-Hinweis und extrahierten Titel
        searchFields.innerHTML = `
            <div style="background: #e8f4f8; padding: 10px; border-radius: 4px; margin-bottom: 10px;">
                📝 Erkannter Titel: <strong>${escapeHtml(extractedTitle)}</strong>
            </div>
            <div id="manual-search-toggle" style="display: none;">
                <input type="text" id="search-title" placeholder="Film/Serie Titel" class="form-control" value="${escapeHtml(extractedTitle)}">
                <select id="search-media-type" class="form-control">
                    <option value="movie" ${mediaType === 'movie' ? 'selected' : ''}>Film</option>
                    <option value="tv" ${mediaType === 'tv' ? 'selected' : ''}>TV-Serie</option>
                </select>
                <button onclick="searchMetadata()" class="btn btn-primary" style="width: 100%; margin-top: 10px;">Erneut suchen</button>
            </div>
        `;
        
        resultsDiv.innerHTML = '<p>🔍 Suche automatisch nach Metadaten...</p>';
        
        // Starte automatische Suche - übergebe ISO-Dateinamen statt extrahiertem Titel
        const isoFilename = isoPath.split('/').pop(); // Extrahiere nur Dateinamen
        autoSearchTMDB(isoFilename, mediaType);
    }
    
    modal.style.display = 'block';
}

// Automatische TMDB-Suche beim Öffnen des Modals (nutzt neues Caching-System)
function autoSearchTMDB(isoFilename, mediaType) {
    const resultsDiv = document.getElementById('metadata-results');
    
    console.log('[TMDB] Starte Suche für ISO:', isoFilename);
    
    fetch('/api/metadata/tmdb/search', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({iso_filename: isoFilename})
    })
    .then(res => {
        console.log('[TMDB] Response Status:', res.status);
        return res.json();
    })
    .then(data => {
        console.log('[TMDB] Response Data:', data);
        
        if (data.success && data.results && data.results.length > 0) {
            console.log(`[TMDB] ${data.total_results} Treffer gefunden (zeige ${data.results.length})`);
            
            if (data.results.length === 1) {
                // Ein Treffer → Modal schließen und direkt übernehmen
                console.log('[TMDB] Eindeutiger Treffer - übernehme automatisch');
                closeMetadataModal();
                applyTMDBMetadata(data.results[0].id, data.results[0].title, data.media_type);
            } else {
                // Mehrere Treffer → Auswahl anzeigen
                console.log('[TMDB] Mehrere Treffer - zeige Auswahl');
                displayTMDBResults(data.results, data.media_type);
                
                // Zeige manuelle Suche als zusätzliche Option
                document.getElementById('manual-search-toggle').style.display = 'block';
            }
        } else {
            // Keine Treffer → Manuelle Eingabe ermöglichen
            console.log('[TMDB] Keine Treffer gefunden');
            resultsDiv.innerHTML = `
                <div style="background: #f8d7da; padding: 15px; border-radius: 4px; margin-bottom: 10px; border-left: 4px solid #dc3545;">
                    <strong>❌ Keine Treffer gefunden</strong><br>
                    <small>Suchbegriff: "${data.search_term || 'unbekannt'}"</small><br>
                    <small>Bitte passen Sie den Suchbegriff an und suchen Sie erneut:</small>
                </div>
            `;
            document.getElementById('manual-search-toggle').style.display = 'block';
        }
    })
    .catch(err => {
        console.error('[TMDB] Fehler:', err);
        resultsDiv.innerHTML = `
            <div style="background: #f8d7da; padding: 15px; border-radius: 4px; margin-bottom: 10px; border-left: 4px solid #dc3545;">
                <strong>❌ Fehler bei der Suche</strong><br>
                <small>${err.message}</small>
            </div>
        `;
        document.getElementById('manual-search-toggle').style.display = 'block';
    });
}

function closeMetadataModal() {
    document.getElementById('metadata-modal').style.display = 'none';
    currentMetadataPath = '';
    currentMetadataType = '';
}

// Click außerhalb des Modals schließt es
document.addEventListener('click', function(event) {
    const modal = document.getElementById('metadata-modal');
    if (modal && event.target === modal) {
        closeMetadataModal();
    }
});

function searchMetadata() {
    const resultsDiv = document.getElementById('metadata-results');
    resultsDiv.innerHTML = '<p>Suche läuft...</p>';
    
    if (currentMetadataType === 'audio') {
        const artist = document.getElementById('search-artist').value.trim();
        const album = document.getElementById('search-album').value.trim();
        
        // Bei .mbquery sind Felder optional
        // Prüfung erfolgt im Backend
        
        fetch('/api/metadata/musicbrainz/search', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({artist, album, iso_path: currentMetadataPath})
        })
        .then(res => res.json())
        .then(data => {
            if (data.success) {
                // Zeige Hinweis wenn .mbquery genutzt wurde
                if (data.used_mbquery) {
                    const hint = document.getElementById('mbquery-hint');
                    if (hint) hint.style.display = 'block';
                }
                displayMusicBrainzResults(data.results);
            } else {
                resultsDiv.innerHTML = `<p class="error">${data.message}</p>`;
            }
        })
        .catch(err => {
            resultsDiv.innerHTML = `<p class="error">Fehler: ${err.message}</p>`;
        });
    } else {
        const title = document.getElementById('search-title').value.trim();
        const mediaType = document.getElementById('search-media-type').value;
        
        if (!title) {
            resultsDiv.innerHTML = '<p class="error">Bitte Titel eingeben</p>';
            return;
        }
        
        fetch('/api/metadata/tmdb/search', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({title, type: mediaType})
        })
        .then(res => res.json())
        .then(data => {
            if (data.success) {
                displayTMDBResults(data.results, mediaType);
            } else {
                resultsDiv.innerHTML = `<p class="error">${data.message}</p>`;
            }
        })
        .catch(err => {
            resultsDiv.innerHTML = `<p class="error">Fehler: ${err.message}</p>`;
        });
    }
}

function displayMusicBrainzResults(results) {
    const resultsDiv = document.getElementById('metadata-results');
    
    if (results.length === 0) {
        resultsDiv.innerHTML = '<p>Keine Treffer gefunden</p>';
        return;
    }
    
    resultsDiv.innerHTML = '<div class="metadata-results-list"></div>';
    const listDiv = resultsDiv.querySelector('.metadata-results-list');
    
    results.forEach(item => {
        const itemDiv = document.createElement('div');
        itemDiv.className = 'metadata-result-item';
        
        // Berechne Laufzeit in MM:SS Format
        let durationStr = '';
        if (item.duration && item.duration > 0) {
            const totalSeconds = Math.floor(item.duration / 1000);
            const hours = Math.floor(totalSeconds / 3600);
            const minutes = Math.floor((totalSeconds % 3600) / 60);
            const seconds = totalSeconds % 60;
            if (hours > 0) {
                durationStr = `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
            } else {
                durationStr = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
            }
        }
        
        const coverUrl = item.id ? `/api/musicbrainz/cover/${item.id}` : '/static/img/audio-cd-placeholder.png';
        
        itemDiv.innerHTML = `
            <div class="result-layout">
                <img src="${coverUrl}" alt="Cover" class="result-cover" onerror="this.src='/static/img/audio-cd-placeholder.png'">
                <div class="result-info">
                    <div class="result-title">${escapeHtml(item.title)}</div>
                    <div class="result-artist">${escapeHtml(item.artist)}</div>
                    <div class="result-details">
                        ${item.date && item.date !== 'unknown' ? `<span class="detail-date">${item.date}</span>` : ''}
                        ${item.country && item.country !== 'unknown' ? `<span class="detail-country">${item.country}</span>` : ''}
                        ${item.label && item.label !== 'Unknown' ? `<span class="detail-label">${escapeHtml(item.label)}</span>` : ''}
                    </div>
                    <div class="result-stats">
                        ${item.tracks ? `<span class="detail-tracks">${item.tracks} Tracks</span>` : ''}
                        ${durationStr ? `<span class="detail-duration">${durationStr}</span>` : ''}
                    </div>
                </div>
                <button class="btn-select-metadata" data-id="${item.id}">Auswählen</button>
            </div>
        `;
        
        itemDiv.querySelector('.btn-select-metadata').addEventListener('click', () => {
            applyMusicBrainzMetadata(item.id);
        });
        
        listDiv.appendChild(itemDiv);
    });
}

function displayTMDBResults(results, mediaType) {
    const resultsDiv = document.getElementById('metadata-results');
    
    if (results.length === 0) {
        resultsDiv.innerHTML = '<p>Keine Treffer gefunden</p>';
        return;
    }
    
    resultsDiv.innerHTML = `
        <div style="background: #fff3cd; padding: 10px; border-radius: 4px; margin-bottom: 15px; border-left: 4px solid #ff9800;">
            <strong>⚠️ ${results.length} Treffer gefunden</strong><br>
            <small>Bitte wählen Sie den richtigen Eintrag aus:</small>
        </div>
        <div class="metadata-results-list"></div>
    `;
    const listDiv = resultsDiv.querySelector('.metadata-results-list');
    
    results.forEach(item => {
        const itemDiv = document.createElement('div');
        itemDiv.className = 'metadata-result-item';
        itemDiv.style.cssText = `
            background: white;
            border: 1px solid #ddd;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 10px;
            display: flex;
            gap: 15px;
            align-items: center;
            cursor: pointer;
            transition: all 0.2s;
        `;
        
        // Nutze local_poster falls vorhanden (gecachtes Bild), sonst poster_url
        const posterSrc = item.local_poster ? `/api/archive/thumbnail/${item.local_poster}` : (item.poster_url || null);
        
        itemDiv.innerHTML = `
            ${posterSrc ? `<img src="${posterSrc}" alt="Poster" style="width: 80px; height: 120px; object-fit: cover; border-radius: 4px; flex-shrink: 0;">` : '<div style="width: 80px; height: 120px; background: #f0f0f0; border-radius: 4px; flex-shrink: 0; display: flex; align-items: center; justify-content: center; font-size: 40px;">🎬</div>'}
            <div style="flex: 1; min-width: 0;">
                <div style="font-size: 16px; font-weight: bold; margin-bottom: 5px; color: #333;">${escapeHtml(item.title)}</div>
                <div style="font-size: 14px; color: #666; margin-bottom: 5px;">📅 ${item.year || 'Jahr unbekannt'}</div>
                ${item.overview ? `<div style="font-size: 13px; color: #888; line-height: 1.4; overflow: hidden; text-overflow: ellipsis; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical;">${escapeHtml(item.overview)}</div>` : ''}
            </div>
            <button class="btn-select-metadata" data-id="${item.id}" data-title="${escapeHtml(item.title)}" style="
                background: #4CAF50;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 4px;
                cursor: pointer;
                font-weight: bold;
                white-space: nowrap;
                flex-shrink: 0;
            ">✓ Auswählen</button>
        `;
        
        // Hover-Effekt
        itemDiv.addEventListener('mouseenter', () => {
            itemDiv.style.borderColor = '#4CAF50';
            itemDiv.style.boxShadow = '0 2px 8px rgba(76, 175, 80, 0.2)';
        });
        itemDiv.addEventListener('mouseleave', () => {
            itemDiv.style.borderColor = '#ddd';
            itemDiv.style.boxShadow = 'none';
        });
        
        itemDiv.querySelector('.btn-select-metadata').addEventListener('click', (e) => {
            e.stopPropagation();
            applyTMDBMetadata(item.id, e.target.dataset.title, mediaType);
        });
        
        // Klick auf ganzes Item
        itemDiv.addEventListener('click', () => {
            itemDiv.querySelector('.btn-select-metadata').click();
        });
        
        listDiv.appendChild(itemDiv);
    });
}

function applyMusicBrainzMetadata(releaseId) {
    const resultsDiv = document.getElementById('metadata-results');
    resultsDiv.innerHTML = '<p>🎵 Erstelle ISO mit korrekten Tags... (2-5 Minuten)</p>';
    
    fetch('/api/metadata/musicbrainz/apply', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
            iso_path: currentMetadataPath,
            release_id: releaseId
        })
    })
    .then(res => res.json())
    .then(data => {
        if (data.success) {
            resultsDiv.innerHTML = '<p class="success">✅ Metadaten erfolgreich hinzugefügt! ISO wurde neu erstellt.</p>';
            setTimeout(() => {
                closeMetadataModal();
                loadArchive();
            }, 2000);
        } else {
            resultsDiv.innerHTML = `<p class="error">❌ ${data.message}</p>`;
        }
    })
    .catch(err => {
        resultsDiv.innerHTML = `<p class="error">❌ Fehler: ${err.message}</p>`;
    });
}

function applyTMDBMetadata(tmdbId, title, mediaType) {
    const resultsDiv = document.getElementById('metadata-results');
    resultsDiv.innerHTML = '<p>🎬 Erstelle Metadaten...</p>';
    
    fetch('/api/metadata/tmdb/apply', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
            iso_path: currentMetadataPath,
            tmdb_id: tmdbId,
            title: title,
            type: mediaType,
            rename_iso: false
        })
    })
    .then(res => res.json())
    .then(data => {
        if (data.success) {
            resultsDiv.innerHTML = '<p class="success">✅ Metadaten erfolgreich hinzugefügt!</p>';
            setTimeout(() => {
                closeMetadataModal();
                loadArchive();
            }, 2000);
        } else {
            resultsDiv.innerHTML = `<p class="error">❌ ${data.message}</p>`;
        }
    })
    .catch(err => {
        resultsDiv.innerHTML = `<p class="error">❌ Fehler: ${err.message}</p>`;
    });
}

// =============================================================================
// ARCHIVE CARD ACTIONS
// =============================================================================

/**
 * Öffnet Metadaten-Suche direkt für ein bestimmtes ISO
 */
function searchMetadataForFile(isoPath, mediaType) {
    openMetadataModal(isoPath, mediaType);
    // Automatisch Suche starten basierend auf Dateiname
    setTimeout(() => {
        const searchButton = document.getElementById('metadata-search-button');
        if (searchButton) {
            searchButton.click();
        }
    }, 500);
}

/**
 * Startet Download einer ISO-Datei
 */
function downloadISO(isoPath) {
    // Erstelle einen versteckten Link zum Download
    const link = document.createElement('a');
    link.href = `/api/archive/download${isoPath}`;
    link.download = isoPath.split('/').pop();
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', function() {
    loadArchive();
    
    // Refresh every 60 seconds
    setInterval(loadArchive, 60000);
});
