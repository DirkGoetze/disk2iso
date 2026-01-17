/**
 * disk2iso - TMDB Movie Selection Modal
 * Handles TMDB movie search results and user selection
 */

let tmdbCheckInterval = null;

/**
 * Start checking for TMDB search results
 */
function startTmdbResultCheck() {
    // Clear any existing interval
    if (tmdbCheckInterval) {
        clearInterval(tmdbCheckInterval);
    }
    
    // Check every 2 seconds
    tmdbCheckInterval = setInterval(checkTmdbResults, 2000);
    
    // Initial check
    checkTmdbResults();
}

/**
 * Stop checking for TMDB results
 */
function stopTmdbResultCheck() {
    if (tmdbCheckInterval) {
        clearInterval(tmdbCheckInterval);
        tmdbCheckInterval = null;
    }
}

/**
 * Check if TMDB results are available
 */
async function checkTmdbResults() {
    try {
        const response = await fetch('/api/tmdb/results');
        
        if (response.ok) {
            const data = await response.json();
            
            if (data.status === 'pending' && data.results && data.results.length > 0) {
                stopTmdbResultCheck();
                showTmdbModal(data);
            }
        }
    } catch (error) {
        console.error('Error checking TMDB results:', error);
    }
}

/**
 * Show TMDB movie selection modal
 */
function showTmdbModal(data) {
    const modal = document.getElementById('tmdbModal');
    if (!modal) {
        console.error('TMDB modal not found');
        return;
    }
    
    const resultsList = document.getElementById('tmdbResultsList');
    resultsList.innerHTML = '';
    
    // Create movie cards
    data.results.forEach((movie, index) => {
        const movieCard = createMovieCard(movie, index);
        resultsList.appendChild(movieCard);
    });
    
    // Show modal
    modal.style.display = 'block';
}

/**
 * Create a movie card element
 */
function createMovieCard(movie, index) {
    const card = document.createElement('div');
    card.className = 'movie-card';
    card.onclick = () => selectTmdbMovie(index);
    
    const posterUrl = movie.poster_path 
        ? `https://image.tmdb.org/t/p/w200${movie.poster_path}`
        : '/static/img/dvd-placeholder.png';
    
    const year = movie.release_date ? movie.release_date.substring(0, 4) : 'N/A';
    const rating = movie.vote_average ? movie.vote_average.toFixed(1) : 'N/A';
    
    card.innerHTML = `
        <div class="movie-poster">
            <img src="${posterUrl}" alt="${escapeHtml(movie.title)}" 
                 onerror="this.src='/static/img/dvd-placeholder.png'">
        </div>
        <div class="movie-info">
            <h3>${escapeHtml(movie.title)}</h3>
            <p class="movie-year">Jahr: ${year}</p>
            <p class="movie-rating">⭐ ${rating}/10</p>
            ${movie.overview ? `<p class="movie-overview">${escapeHtml(movie.overview.substring(0, 150))}${movie.overview.length > 150 ? '...' : ''}</p>` : ''}
        </div>
    `;
    
    return card;
}

/**
 * Select a movie from TMDB results
 */
async function selectTmdbMovie(index) {
    try {
        const response = await fetch('/api/tmdb/select', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ index: index })
        });
        
        const result = await response.json();
        
        if (result.success) {
            closeTmdbModal();
            
            // Show success message
            const notification = document.createElement('div');
            notification.className = 'notification success';
            notification.textContent = 'Film ausgewählt - Metadaten werden erstellt...';
            document.body.appendChild(notification);
            
            setTimeout(() => {
                notification.remove();
            }, 3000);
        } else {
            alert('Fehler beim Auswählen: ' + result.message);
        }
    } catch (error) {
        console.error('Error selecting TMDB movie:', error);
        alert('Fehler beim Auswählen des Films');
    }
}

/**
 * Close TMDB modal
 */
function closeTmdbModal() {
    const modal = document.getElementById('tmdbModal');
    if (modal) {
        modal.style.display = 'none';
    }
}

/**
 * Escape HTML to prevent XSS
 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// DISABLED: Auto-start deaktiviert - Neuer Workflow in archive.js
// Das alte Polling-System wird nicht mehr verwendet
// Start checking only if TMDB modal exists (i.e., on archive page)
// This prevents unnecessary 404 errors on other pages
/*
if (document.getElementById('tmdbModal')) {
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startTmdbResultCheck);
    } else {
        startTmdbResultCheck();
    }
}
*/
