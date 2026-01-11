/**
 * disk2iso - Help Page JavaScript
 */

let currentDoc = 'Handbuch.md';

// Konfiguriere marked.js
marked.setOptions({
    breaks: true,
    gfm: true,
    headerIds: true,
    mangle: false
});

// Lade Dokumentation beim Seitenaufruf
document.addEventListener('DOMContentLoaded', function() {
    loadDocument(currentDoc);
    
    // Event-Listener für Dokumenten-Links
    document.querySelectorAll('.docs-menu a').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const doc = this.getAttribute('data-doc');
            loadDocument(doc);
            
            // Aktualisiere aktive Klasse
            document.querySelectorAll('.docs-menu a').forEach(a => a.classList.remove('active'));
            this.classList.add('active');
        });
    });
});

function loadDocument(filename) {
    currentDoc = filename;
    const container = document.getElementById('markdown-content');
    
    container.innerHTML = '<p style="text-align: center; padding: 40px; color: #666;">Lade Dokumentation...</p>';
    
    fetch(`/static/docs/${filename}`)
        .then(response => {
            if (!response.ok) {
                throw new Error('Dokument nicht gefunden');
            }
            return response.text();
        })
        .then(markdown => {
            // Konvertiere Markdown zu HTML
            const html = marked.parse(markdown);
            container.innerHTML = html;
            
            // Scrolle nach oben
            container.scrollTop = 0;
            
            // Style für Code-Blöcke
            container.querySelectorAll('pre code').forEach(block => {
                block.style.display = 'block';
                block.style.padding = '15px';
                block.style.background = '#f5f5f5';
                block.style.borderRadius = '4px';
                block.style.overflow = 'auto';
            });
            
            // Style für Tabellen
            container.querySelectorAll('table').forEach(table => {
                table.style.width = '100%';
                table.style.borderCollapse = 'collapse';
                table.style.marginTop = '15px';
                table.style.marginBottom = '15px';
            });
            
            container.querySelectorAll('table th, table td').forEach(cell => {
                cell.style.border = '1px solid #ddd';
                cell.style.padding = '8px';
                cell.style.textAlign = 'left';
            });
            
            container.querySelectorAll('table th').forEach(th => {
                th.style.background = '#f8f9fa';
                th.style.fontWeight = '600';
            });
        })
        .catch(error => {
            console.error('Fehler beim Laden:', error);
            container.innerHTML = `
                <div style="text-align: center; padding: 40px;">
                    <p style="color: #dc3545; font-size: 1.2em;">⚠️ Fehler beim Laden der Dokumentation</p>
                    <p style="color: #666;">${error.message}</p>
                </div>
            `;
        });
}
