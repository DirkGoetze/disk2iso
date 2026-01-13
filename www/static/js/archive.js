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
    const div = document.createElement('div');
    div.className = 'archive-item';
    
    // Prüfe ob Metadaten fehlen (Disc_* Pattern oder keine .nfo)
    const needsMetadata = file.name.startsWith('Disc_') || file.name.startsWith('disc_') || !file.metadata;
    const isAudioCD = file.path.includes('/audio/');
    const isDVDorBD = file.path.includes('/dvd/') || file.path.includes('/bd/');
    
    // Wenn Metadaten vorhanden sind (Audio-CD, DVD oder Blu-ray mit .nfo)
    if (file.metadata) {
        const meta = file.metadata;
        let thumbUrl, placeholderUrl;
        
        if (meta.type === 'audio-cd') {
            thumbUrl = file.thumbnail ? `/api/archive/thumbnail/${file.thumbnail}` : '/static/img/audio-cd-placeholder.png';
            placeholderUrl = '/static/img/audio-cd-placeholder.png';
            
            div.innerHTML = `
                <div class="archive-item-layout">
                    <img src="${thumbUrl}" alt="Cover" class="archive-cover" onerror="this.src='${placeholderUrl}'">
                    <div class="archive-info">
                        <div class="archive-title">${escapeHtml(meta.title || file.name)}</div>
                        <div class="archive-artist">${escapeHtml(meta.artist || 'Unknown Artist')}</div>
                        <div class="archive-details">
                            <i>${meta.date || 'Unknown'} ${meta.country && meta.country !== 'unknown' ? meta.country : ''}</i>
                            (${meta.tracks || 0} Tracks${meta.duration ? ' / ' + meta.duration : ''})
                        </div>
                        <div class="archive-meta">
                            <span>💾 ${formatBytes(file.size)}</span>
                            <span>📅 ${formatDate(file.modified)}</span>
                        </div>
                    </div>
                </div>
            `;
        } else if (meta.type === 'dvd-video' || meta.type === 'bd-video') {
            thumbUrl = file.thumbnail ? `/api/archive/thumbnail/${file.thumbnail}` : '/static/img/dvd-placeholder.png';
            placeholderUrl = '/static/img/dvd-placeholder.png';
            
            const mediaType = meta.type === 'bd-video' ? 'Blu-ray' : 'DVD';
            const runtime = meta.runtime ? `${meta.runtime} Min.` : '';
            
            // Extrahiere Season/Disc Info aus Dateinamen (z.B. "supernatural_season_10_disc_2")
            const filename = file.name.toLowerCase().replace('.iso', '');
            let seasonInfo = '';
            
            const seasonMatch = filename.match(/season[_\s]*(\d+)/i);
            const discMatch = filename.match(/dis[ck][_\s]*(\d+)/i);
            
            if (seasonMatch || discMatch) {
                // Serien-DVD: Zeige Season/Disc statt Regisseur
                let parts = [];
                if (seasonMatch) parts.push(`Season ${seasonMatch[1]}`);
                if (discMatch) parts.push(`Disc ${discMatch[1]}`);
                seasonInfo = parts.join(' • ');
            }
            
            // Zweite Zeile: Season/Disc bei Serien, Regisseur bei Filmen
            const secondLine = seasonInfo || escapeHtml(meta.director || 'Unknown Director');
            
            div.innerHTML = `
                <div class="archive-item-layout">
                    <img src="${thumbUrl}" alt="Poster" class="archive-cover movie-poster" onerror="this.src='${placeholderUrl}'">
                    <div class="archive-info">
                        <div class="archive-title">${escapeHtml(meta.title || file.name)}</div>
                        <div class="archive-artist">${secondLine}</div>
                        <div class="archive-details">
                            <i>${meta.year || 'Unknown'} • ${meta.genre || 'Unknown Genre'}</i>
                            ${runtime ? `(${runtime})` : ''}
                            ${meta.rating ? ` ⭐ ${meta.rating}/10` : ''}
                        </div>
                        <div class="archive-meta">
                            <span>🎬 ${mediaType}</span>
                            <span>💾 ${formatBytes(file.size)}</span>
                            <span>📅 ${formatDate(file.modified)}</span>
                        </div>
                    </div>
                </div>
            `;
        } else {
            // Unbekannter Metadaten-Typ → Einfache Anzeige
            div.innerHTML = `
                <div class="archive-item-header">
                    <span class="archive-filename">${escapeHtml(file.name)}</span>
                    <span class="archive-size">${formatBytes(file.size)}</span>
                </div>
                <div class="archive-item-meta">
                    <span>📅 ${formatDate(file.modified)}</span>
                </div>
            `;
        }
    } else {
        // Fallback: Einfache Anzeige ohne Metadaten
        div.innerHTML = `
            <div class="archive-item-header">
                <span class="archive-filename">${escapeHtml(file.name)}</span>
                <span class="archive-size">${formatBytes(file.size)}</span>
            </div>
            <div class="archive-item-meta">
                <span>📅 ${formatDate(file.modified)}</span>
                ${needsMetadata && (isAudioCD || isDVDorBD) ? '<button class="btn-add-metadata" data-path="' + file.path + '" data-type="' + (isAudioCD ? 'audio' : 'video') + '">📝 Metadaten hinzufügen</button>' : ''}
            </div>
        `;
    }
    
    // Event-Listener für Metadaten-Button
    if (needsMetadata && (isAudioCD || isDVDorBD)) {
        const metadataBtn = div.querySelector('.btn-add-metadata');
        if (metadataBtn) {
            metadataBtn.addEventListener('click', () => {
                openMetadataModal(file.path, metadataBtn.dataset.type);
            });
        }
    }
    
    return div;
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

function openMetadataModal(isoPath, type) {
    currentMetadataPath = isoPath;
    currentMetadataType = type;
    
    const modal = document.getElementById('metadata-modal');
    const searchType = document.getElementById('metadata-search-type');
    const searchFields = document.getElementById('metadata-search-fields');
    
    if (type === 'audio') {
        searchType.textContent = 'MusicBrainz-Suche';
        searchFields.innerHTML = `
            <input type="text" id="search-artist" placeholder="Künstler" class="form-control">
            <input type="text" id="search-album" placeholder="Album" class="form-control">
        `;
    } else {
        searchType.textContent = 'TMDB-Suche';
        searchFields.innerHTML = `
            <input type="text" id="search-title" placeholder="Film/Serie Titel" class="form-control">
            <select id="search-media-type" class="form-control">
                <option value="movie">Film</option>
                <option value="tv">TV-Serie</option>
            </select>
        `;
    }
    
    document.getElementById('metadata-results').innerHTML = '';
    modal.style.display = 'block';
}

function closeMetadataModal() {
    document.getElementById('metadata-modal').style.display = 'none';
    currentMetadataPath = '';
    currentMetadataType = '';
}

function searchMetadata() {
    const resultsDiv = document.getElementById('metadata-results');
    resultsDiv.innerHTML = '<p>Suche läuft...</p>';
    
    if (currentMetadataType === 'audio') {
        const artist = document.getElementById('search-artist').value.trim();
        const album = document.getElementById('search-album').value.trim();
        
        if (!artist && !album) {
            resultsDiv.innerHTML = '<p class="error">Bitte Künstler oder Album eingeben</p>';
            return;
        }
        
        fetch('/api/metadata/musicbrainz/search', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({artist, album})
        })
        .then(res => res.json())
        .then(data => {
            if (data.success) {
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
        
        const coverUrl = item.cover_url || '/static/img/audio-cd-placeholder.png';
        
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
    
    resultsDiv.innerHTML = '<div class="metadata-results-list"></div>';
    const listDiv = resultsDiv.querySelector('.metadata-results-list');
    
    results.forEach(item => {
        const itemDiv = document.createElement('div');
        itemDiv.className = 'metadata-result-item';
        itemDiv.innerHTML = `
            ${item.poster_url ? `<img src="${item.poster_url}" alt="Poster" class="result-poster">` : ''}
            <div class="result-info">
                <div class="result-title">${escapeHtml(item.title)}</div>
                <div class="result-details">${item.year || 'Unknown'}</div>
                ${item.overview ? `<div class="result-overview">${escapeHtml(item.overview.substring(0, 150))}...</div>` : ''}
            </div>
            <button class="btn-select-metadata" data-id="${item.id}" data-title="${escapeHtml(item.title)}">Auswählen</button>
        `;
        
        itemDiv.querySelector('.btn-select-metadata').addEventListener('click', (e) => {
            applyTMDBMetadata(item.id, e.target.dataset.title, mediaType);
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

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', function() {
    loadArchive();
    
    // Refresh every 60 seconds
    setInterval(loadArchive, 60000);
});
