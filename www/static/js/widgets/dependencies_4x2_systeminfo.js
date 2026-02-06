/**
 * Dependencies Widget (4x1) - Systeminfo
 * Zeigt Core-System-Tools (ddrescue, genisoimage, python, flask, etc.)
 * Version: 1.0.0
 */

function loadSystemInfoDependencies() {
    fetch('/api/widgets/systeminfo/dependencies')
        .then(response => response.json())
        .then(data => {
            if (data.success && data.software) {
                updateSystemInfoDependencies(data.software);
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden der System-Dependencies:', error);
            showSystemInfoDependenciesError();
        });
}

function updateSystemInfoDependencies(softwareList) {
    const tbody = document.getElementById('systeminfo-dependencies-tbody');
    if (!tbody) return;
    
    // Definiere Core-Tools (Tools die vom Core-System benötigt werden)
    const coreTools = [
        { name: 'ddrescue', display_name: 'GNU ddrescue' },
        { name: 'genisoimage', display_name: 'genisoimage' },
        { name: 'python', display_name: 'Python' },
        { name: 'flask', display_name: 'Flask' }
    ];
    
    let html = '';
    
    coreTools.forEach(tool => {
        const software = softwareList.find(s => s.name === tool.name);
        if (software) {
            html += renderSoftwareRow(tool.display_name, software);
        }
    });
    
    if (html === '') {
        html = '<tr><td colspan="4" style="text-align: center; padding: 20px; color: #999;">Keine Informationen verfügbar</td></tr>';
    }
    
    tbody.innerHTML = html;
}

function showSystemInfoDependenciesError() {
    const tbody = document.getElementById('systeminfo-dependencies-tbody');
    if (!tbody) return;
    
    tbody.innerHTML = '<tr><td colspan="4" style="text-align: center; padding: 20px; color: #e53e3e;">Fehler beim Laden</td></tr>';
}

// Gemeinsame Hilfsfunktionen für Software-Widgets
if (typeof renderSoftwareRow !== 'function') {
    function renderSoftwareRow(displayName, software) {
        const installedVersion = software.installed_version || '-';
        const availableVersion = software.available_version || '-';
        const status = software.status || 'unknown';
        const updateAvailable = software.update_available || false;
        
        // Status-Badge
        let statusBadge = '';
        let rowClass = '';
        
        if (status === 'missing') {
            statusBadge = '<span class="status-badge status-missing">❌ Fehlt</span>';
            rowClass = 'row-inactive';
        } else if (status === 'outdated' || updateAvailable) {
            statusBadge = '<span class="status-badge status-outdated">⚠️ Veraltet</span>';
            rowClass = 'row-warning';
        } else if (status === 'current') {
            statusBadge = '<span class="status-badge status-current">✅ Aktuell</span>';
        } else {
            statusBadge = '<span class="status-badge status-unknown">❓ Unbekannt</span>';
        }
        
        // Aktions-Button
        let actionButton = '';
        if (status === 'missing') {
            actionButton = `<button class="btn btn-primary btn-install" onclick="installSoftware('${software.name}', this)" title="Software installieren">
                <span class="btn-icon">⬇️</span> Installieren
            </button>`;
        } else if (status === 'outdated' || updateAvailable) {
            actionButton = `<button class="btn btn-update" onclick="installSoftware('${software.name}', this)" title="Software aktualisieren">
                <span class="btn-icon">↻</span> Update
            </button>`;
        } else {
            actionButton = '<span style="color: #999; font-size: 0.85em;">-</span>';
        }
        
        return `
            <tr class="${rowClass}">
                <td><strong>${displayName}</strong></td>
                <td>${installedVersion}</td>
                <td>${availableVersion} ${statusBadge}</td>
                <td>${actionButton}</td>
            </tr>
        `;
    }
    
    function installSoftware(softwareName, buttonElement) {
        // Button deaktivieren während Installation
        const originalHtml = buttonElement.innerHTML;
        buttonElement.disabled = true;
        buttonElement.innerHTML = '<span class="btn-icon">⌛</span> Installiere...';
        
        fetch(`/api/software/install/${softwareName}`, { method: 'POST' })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    buttonElement.innerHTML = '<span class="btn-icon">✅</span> Fertig!';
                    buttonElement.classList.add('btn-success');
                    
                    // Widget nach 2 Sekunden neu laden
                    setTimeout(() => {
                        location.reload();
                    }, 2000);
                } else {
                    buttonElement.innerHTML = '<span class="btn-icon">❌</span> Fehler';
                    buttonElement.classList.add('btn-error');
                    console.error('Installation fehlgeschlagen:', data.error);
                    
                    // Button nach 3 Sekunden zurücksetzen
                    setTimeout(() => {
                        buttonElement.innerHTML = originalHtml;
                        buttonElement.disabled = false;
                        buttonElement.classList.remove('btn-error');
                    }, 3000);
                }
            })
            .catch(error => {
                buttonElement.innerHTML = '<span class="btn-icon">❌</span> Fehler';
                buttonElement.classList.add('btn-error');
                console.error('Netzwerkfehler:', error);
                
                setTimeout(() => {
                    buttonElement.innerHTML = originalHtml;
                    buttonElement.disabled = false;
                    buttonElement.classList.remove('btn-error');
                }, 3000);
            });
    }
}

// Gemeinsame Toggle-Funktion (falls nicht bereits in system.js vorhanden)
if (typeof toggleCategory !== 'function') {
    function toggleCategory(header) {
        const category = header.parentElement;
        const content = category.querySelector('.category-content');
        const icon = header.querySelector('.toggle-icon');
        
        if (content.style.display === 'none') {
            content.style.display = 'block';
            icon.textContent = '▼';
            category.classList.remove('category-collapsed');
        } else {
            content.style.display = 'none';
            icon.textContent = '▶';
            category.classList.add('category-collapsed');
        }
    }
}

// Auto-Load (kein Auto-Update nötig, Software ändert sich nicht oft)
if (document.getElementById('systeminfo-dependencies-widget')) {
    loadSystemInfoDependencies();
}
