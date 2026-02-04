/**
 * System Info - Core Dependencies Widget (4x1)
 * Zeigt Core-System-Tools (ddrescue, genisoimage, python, flask, etc.)
 * Version: 1.0.0
 */

function loadSystemInfoDependencies() {
    fetch('/api/system')
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
            const statusBadge = getStatusBadge(software);
            const rowClass = !software.installed_version ? 'row-inactive' : '';
            
            html += `
                <tr class="${rowClass}">
                    <td><strong>${tool.display_name}</strong></td>
                    <td>${software.installed_version || '<em>Nicht installiert</em>'}</td>
                    <td>${statusBadge}</td>
                </tr>
            `;
        }
    });
    
    if (html === '') {
        html = '<tr><td colspan="3" style="text-align: center; padding: 20px; color: #999;">Keine Informationen verfügbar</td></tr>';
    }
    
    tbody.innerHTML = html;
}

function showSystemInfoDependenciesError() {
    const tbody = document.getElementById('systeminfo-dependencies-tbody');
    if (!tbody) return;
    
    tbody.innerHTML = '<tr><td colspan="3" style="text-align: center; padding: 20px; color: #e53e3e;">Fehler beim Laden</td></tr>';
}

// Gemeinsame Hilfsfunktion (falls nicht bereits in system.js vorhanden)
if (typeof getStatusBadge !== 'function') {
    function getStatusBadge(item) {
        if (!item.installed_version) {
            return '<span class="version-badge version-error">❌ Nicht installiert</span>';
        }
        return '<span class="version-badge version-current">✅ Installiert</span>';
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
