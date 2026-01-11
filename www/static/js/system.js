/**
 * disk2iso - System Page JavaScript
 */

let isRefreshing = false;

function loadSystemInfo() {
    if (isRefreshing) return;
    
    fetch('/api/system')
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                displayOsInfo(data.os);
                displayDisk2IsoInfo(data.disk2iso);
                displaySoftwareVersions(data.software);
            } else {
                showError('Fehler beim Laden der Systeminformationen');
            }
        })
        .catch(error => {
            console.error('Fehler:', error);
            showError('Fehler beim Laden der Systeminformationen: ' + error);
        });
}

function displayOsInfo(os) {
    const container = document.getElementById('os-info');
    container.innerHTML = `
        <div class="info-item">
            <span class="info-label">Distribution</span>
            <span class="info-value">${os.distribution || 'Unbekannt'}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Version</span>
            <span class="info-value">${os.version || 'Unbekannt'}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Kernel</span>
            <span class="info-value">${os.kernel || 'Unbekannt'}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Architektur</span>
            <span class="info-value">${os.architecture || 'Unbekannt'}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Hostname</span>
            <span class="info-value">${os.hostname || 'Unbekannt'}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Uptime</span>
            <span class="info-value">${os.uptime || 'Unbekannt'}</span>
        </div>
    `;
}

function displayDisk2IsoInfo(info) {
    const container = document.getElementById('disk2iso-info');
    const statusClass = info.service_status === 'active' ? 'status-ok' : 
                      info.service_status === 'inactive' ? 'status-warning' : 'status-error';
    
    container.innerHTML = `
        <div class="info-item">
            <span class="info-label">Version</span>
            <span class="info-value">${info.version || 'Unbekannt'}</span>
        </div>
        <div class="info-item">
            <span class="info-label">Service Status</span>
            <span class="info-value">
                <span class="status-indicator-small ${statusClass}"></span>
                ${info.service_status || 'Unbekannt'}
            </span>
        </div>
        <div class="info-item">
            <span class="info-label">Installationspfad</span>
            <span class="info-value">${info.install_path || '/opt/disk2iso'}</span>
        </div>
    `;
}

function displaySoftwareVersions(software) {
    const container = document.getElementById('software-container');
    
    // Definiere Kategorien in gewünschter Reihenfolge mit Typ-Kennzeichnung
    const categoryDefinitions = [
        {
            name: 'System Tools',
            tools: ['ddrescue', 'genisoimage'],
            optional: false
        },
        {
            name: 'Audio-CD Tools',
            tools: ['cdparanoia', 'lame'],
            optional: false
        },
        {
            name: 'DVD Tools',
            tools: ['dvdbackup'],
            optional: false
        },
        {
            name: 'Blu-ray Tools',
            tools: [],
            optional: true
        },
        {
            name: 'UI Tools',
            tools: ['python', 'flask', 'mosquitto'],
            optional: true
        }
    ];
    
    let html = '';
    
    categoryDefinitions.forEach(categoryDef => {
        const items = software.filter(s => categoryDef.tools.includes(s.name));
        
        // Prüfe ob mindestens ein Tool installiert ist
        const hasInstalledTools = items.some(item => item.installed_version);
        
        // Für leere optionale Kategorien: Zeige nur eingeklappte Überschrift
        if (items.length === 0 && categoryDef.optional) {
            html += `
                <div class="software-category category-collapsed">
                    <h3 class="category-toggle category-header-inactive" onclick="toggleCategory(this)">
                        <span class="toggle-icon">▶</span>
                        ${categoryDef.name}
                        <span style="color: #999; font-size: 0.9em; font-weight: normal;"> (Nicht installiert)</span>
                    </h3>
                    <div class="category-content" style="display: none;">
                        <p style="padding: 15px; color: #999; text-align: center;">Keine Tools installiert</p>
                    </div>
                </div>
            `;
            return;
        }
        
        // Überspringe leere nicht-optionale Kategorien
        if (items.length === 0) return;
        
        const categoryClass = (!hasInstalledTools && categoryDef.optional) ? 'category-collapsed' : '';
        const headerClass = (!hasInstalledTools && categoryDef.optional) ? 'category-header-inactive' : '';
        
        html += `
            <div class="software-category ${categoryClass}">
                <h3 class="category-toggle ${headerClass}" onclick="toggleCategory(this)">
                    <span class="toggle-icon">${(!hasInstalledTools && categoryDef.optional) ? '▶' : '▼'}</span>
                    ${categoryDef.name}
                    ${(!hasInstalledTools && categoryDef.optional) ? '<span style="color: #999; font-size: 0.9em; font-weight: normal;"> (Nicht installiert)</span>' : ''}
                </h3>
                <div class="category-content" style="display: ${(!hasInstalledTools && categoryDef.optional) ? 'none' : 'block'};">
                    <table class="software-table">
                        <thead>
                            <tr>
                                <th>Software</th>
                                <th>Version</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>
        `;
        
        items.forEach(item => {
            const statusBadge = getStatusBadge(item);
            const rowClass = !item.installed_version ? 'row-inactive' : '';
            
            html += `
                <tr class="${rowClass}">
                    <td><strong>${item.display_name || item.name}</strong></td>
                    <td>${item.installed_version || '<em>Nicht installiert</em>'}</td>
                    <td>${statusBadge}</td>
                </tr>
            `;
        });
        
        html += `
                        </tbody>
                    </table>
                </div>
            </div>
        `;
    });
    
    if (html === '') {
        html = '<p style="text-align: center; padding: 40px; color: #666;">Keine Software-Informationen verfügbar</p>';
    }
    
    container.innerHTML = html;
}

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

function getStatusBadge(item) {
    if (!item.installed_version) {
        return '<span class="version-badge version-error">❌ Nicht installiert</span>';
    }
    
    return '<span class="version-badge version-current">✅ Installiert</span>';
}

function refreshSystemInfo() {
    if (isRefreshing) return;
    
    isRefreshing = true;
    const refreshIcon = document.getElementById('refresh-icon');
    const container = document.getElementById('software-container');
    
    // Rotation animation
    refreshIcon.style.display = 'inline-block';
    refreshIcon.style.animation = 'spin 1s linear infinite';
    container.classList.add('loading');
    
    loadSystemInfo();
    
    // Reset nach 2 Sekunden
    setTimeout(() => {
        isRefreshing = false;
        refreshIcon.style.animation = '';
        container.classList.remove('loading');
    }, 2000);
}

function showError(message) {
    const container = document.getElementById('software-container');
    container.innerHTML = `
        <div style="background: #ffe3e3; border-left: 4px solid #c92a2a; padding: 20px; border-radius: 4px;">
            <strong>⚠️ Fehler</strong><br>
            ${message}
        </div>
    `;
}

// Initialisierung beim Laden der Seite
document.addEventListener('DOMContentLoaded', function() {
    loadSystemInfo();
});
