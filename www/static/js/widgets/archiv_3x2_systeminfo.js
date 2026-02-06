/**
 * Archiv Widget (2x1) - Systeminfo
 * Lädt dynamisch Archiv-Statistiken basierend auf Ordnerstruktur
 * Version: 1.0.0
 */

function loadArchivWidget() {
    fetch('/api/widgets/systeminfo/archiv')
        .then(response => response.json())
        .then(data => {
            if (data.success && data.archive_counts) {
                updateArchivWidget(data.archive_counts);
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden der Archiv-Informationen:', error);
            showArchivWidgetError();
        });
}

function updateArchivWidget(archiveCounts) {
    const container = document.getElementById('archiv-widget-content');
    if (!container) return;
    
    // Definiere Reihenfolge und Ordnernamen für Anzeige
    const typeOrder = [
        { key: 'data', folder: '/data' },
        { key: 'audio', folder: '/audio' },
        { key: 'dvd', folder: '/dvd' },
        { key: 'bluray', folder: '/bd' }
    ];
    
    let html = '';
    
    // Rendere nur Typen die Dateien enthalten
    typeOrder.forEach(type => {
        const count = archiveCounts[type.key] || 0;
        
        // Zeige Zeile nur wenn Dateien vorhanden
        if (count > 0) {
            html += `
                <div class="info-row">
                    <span class="info-label">${type.folder}</span>
                    <span class="info-value">${count}</span>
                </div>
            `;
        }
    });
    
    // Fallback wenn keine Archive vorhanden
    if (html === '') {
        html = `
            <div class="info-row" style="justify-content: center; color: #999;">
                <span>Keine Archive vorhanden</span>
            </div>
        `;
    }
    
    container.innerHTML = html;
}

function showArchivWidgetError() {
    const container = document.getElementById('archiv-widget-content');
    if (!container) return;
    
    container.innerHTML = `
        <div class="info-row" style="justify-content: center; color: #e53e3e;">
            <span>Fehler beim Laden</span>
        </div>
    `;
}

// Auto-Update alle 60 Sekunden (Archive ändern sich langsam)
if (document.getElementById('systeminfo-archiv-widget')) {
    loadArchivWidget();
    setInterval(loadArchivWidget, 60000);
}
