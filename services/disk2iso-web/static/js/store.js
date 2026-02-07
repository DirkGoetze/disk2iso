/**
 * disk2iso Store Page
 * Version: 1.0.0
 */

let catalogData = null;

// Initialize store page
document.addEventListener('DOMContentLoaded', function() {
    console.log('Store page initialized');
    loadStoreCatalog();
});

/**
 * Load catalog from API
 */
async function loadStoreCatalog() {
    try {
        const response = await fetch('/api/store/catalog');
        const data = await response.json();
        
        if (data.success) {
            catalogData = data.catalog;
            console.log('Catalog loaded:', catalogData);
            renderStore();
        } else {
            console.error('Failed to load catalog:', data.error);
            showError('Fehler beim Laden des Katalogs');
        }
    } catch (error) {
        console.error('Error loading catalog:', error);
        showError('Katalog konnte nicht geladen werden');
    }
}

/**
 * Render the store page
 */
function renderStore() {
    if (!catalogData) {
        console.error('No catalog data available');
        return;
    }

    // Update category titles and descriptions
    updateCategoryTitles();
    
    // Render modules by category
    renderModulesByCategory('core');
    renderModulesByCategory('optional');
    renderModulesByCategory('providers');
}

/**
 * Update category titles from catalog
 */
function updateCategoryTitles() {
    const lang = 'de'; // TODO: Get from user preferences
    
    catalogData.categories.forEach(category => {
        const titleElement = document.getElementById(`${category.id}-category-title`);
        if (titleElement) {
            const icon = titleElement.querySelector('img');
            const iconHTML = icon ? icon.outerHTML : '';
            titleElement.innerHTML = iconHTML + (category[`name_${lang}`] || category.name);
        }
    });
}

/**
 * Render modules for a specific category
 */
function renderModulesByCategory(categoryId) {
    const container = document.getElementById(`${categoryId}-modules-container`);
    if (!container) {
        console.warn(`Container for category ${categoryId} not found`);
        return;
    }

    container.innerHTML = ''; // Clear existing content
    
    // Filter modules by category
    const modules = Object.entries(catalogData.modules).filter(([moduleId, moduleData]) => {
        // Determine category based on module ID
        if (categoryId === 'core' && moduleId === 'core') return true;
        if (categoryId === 'optional' && ['audio', 'dvd', 'bluray', 'metadata', 'mqtt'].includes(moduleId)) return true;
        if (categoryId === 'providers' && ['musicbrainz', 'tmdb'].includes(moduleId)) return true;
        return false;
    });

    if (modules.length === 0) {
        container.innerHTML = '<p class="no-modules">Keine Module in dieser Kategorie</p>';
        return;
    }

    // Create module cards
    modules.forEach(([moduleId, moduleData]) => {
        const card = createModuleCard(moduleId, moduleData);
        container.appendChild(card);
    });
}

/**
 * Create a module card element
 */
function createModuleCard(moduleId, moduleData) {
    const card = document.createElement('div');
    card.className = 'module-card';
    card.dataset.moduleId = moduleId;
    
    // Determine status
    const isInstalled = moduleData.enabled;
    const isRequired = moduleData.required;
    const statusClass = isInstalled ? 'installed' : 'available';
    const statusText = isRequired ? 'Core' : (isInstalled ? 'Installiert' : 'Verfügbar');
    
    card.innerHTML = `
        <div class="module-card-header">
            <div class="module-icon">
                <img src="${getModuleIcon(moduleId)}" alt="${moduleId}" style="width:32px;height:32px;">
            </div>
            <div class="module-info">
                <h4 class="module-name">${getModuleName(moduleId)}</h4>
                <span class="module-status ${statusClass}">${statusText}</span>
            </div>
        </div>
        <div class="module-card-body">
            <p class="module-description">${getModuleDescription(moduleId)}</p>
            <div class="module-meta">
                <span class="module-version">v${getModuleVersion(moduleId)}</span>
            </div>
        </div>
        <div class="module-card-footer">
            ${createModuleActions(moduleId, moduleData)}
        </div>
    `;
    
    return card;
}

/**
 * Get module icon based on module ID
 */
function getModuleIcon(moduleId) {
    const iconMap = {
        'core': '/static/img/control.svg',
        'audio': '/static/img/audio.svg',
        'dvd': '/static/img/dvd.svg',
        'bluray': '/static/img/bluray.svg',
        'metadata': '/static/img/data.svg',
        'mqtt': '/static/img/plugin.svg',
        'musicbrainz': '/static/img/data.svg',
        'tmdb': '/static/img/data.svg'
    };
    return iconMap[moduleId] || '/static/img/package.svg';
}

/**
 * Get module name
 */
function getModuleName(moduleId) {
    const nameMap = {
        'core': 'disk2iso Core',
        'audio': 'Audio-CD Modul',
        'dvd': 'DVD-Video Modul',
        'bluray': 'Blu-ray Modul',
        'metadata': 'Metadata Modul',
        'mqtt': 'MQTT Integration',
        'musicbrainz': 'MusicBrainz Provider',
        'tmdb': 'TMDB Provider'
    };
    return nameMap[moduleId] || moduleId;
}

/**
 * Get module description
 */
function getModuleDescription(moduleId) {
    const descMap = {
        'core': 'Hauptsystem mit Web-UI und Basis-Funktionalität',
        'audio': 'Rippen von Audio-CDs mit MusicBrainz-Integration',
        'dvd': 'Kopieren von DVD-Video Discs mit Menü-Unterstützung',
        'bluray': 'Kopieren von Blu-ray Discs',
        'metadata': 'Erweiterte Metadaten-Verwaltung und Cover-Art',
        'mqtt': 'MQTT-Integration für Home Assistant',
        'musicbrainz': 'MusicBrainz Metadaten für Audio-CDs',
        'tmdb': 'TMDB Metadaten für Filme und Serien'
    };
    return descMap[moduleId] || 'Keine Beschreibung verfügbar';
}

/**
 * Get module version
 */
function getModuleVersion(moduleId) {
    return '1.3.0'; // TODO: Load from manifest
}

/**
 * Create action buttons for module
 */
function createModuleActions(moduleId, moduleData) {
    if (moduleData.required) {
        return '<button class="btn-secondary" disabled>Core-Modul</button>';
    }
    
    if (moduleData.enabled) {
        return `
            <button class="btn-secondary" onclick="viewModuleDetails('${moduleId}')">Details</button>
            <button class="btn-warning" onclick="disableModule('${moduleId}')">Deaktivieren</button>
        `;
    } else {
        return `
            <button class="btn-primary" onclick="installModule('${moduleId}')">Installieren</button>
            <button class="btn-secondary" onclick="viewModuleDetails('${moduleId}')">Details</button>
        `;
    }
}

/**
 * Install a module
 */
function installModule(moduleId) {
    console.log('Installing module:', moduleId);
    alert(`Installation von ${moduleId} wird in einer zukünftigen Version verfügbar sein.`);
}

/**
 * Disable a module
 */
function disableModule(moduleId) {
    console.log('Disabling module:', moduleId);
    alert(`Deaktivierung von ${moduleId} wird in einer zukünftigen Version verfügbar sein.`);
}

/**
 * View module details
 */
function viewModuleDetails(moduleId) {
    console.log('Viewing details for:', moduleId);
    alert(`Details für ${moduleId} werden in einer zukünftigen Version angezeigt.`);
}

/**
 * Show error message
 */
function showError(message) {
    const containers = ['core-modules-container', 'optional-modules-container', 'providers-modules-container'];
    containers.forEach(containerId => {
        const container = document.getElementById(containerId);
        if (container) {
            container.innerHTML = `<p class="error-message">${message}</p>`;
        }
    });
}

/**
 * Refresh store content
 */
function refreshStore() {
    console.log('Refreshing store...');
    loadStoreCatalog();
}
