/**
 * disk2iso - Config Widget Settings
 * Dynamisches Laden und Verwalten der System-Einstellungen (Output Dir, Sprache)
 * Auto-Save bei Fokus-Verlust (moderne UX)
 */

(function() {
    'use strict';

    let currentBrowserPath = '/';

    /**
     * Lädt das Config Settings Widget vom Backend
     */
    async function loadConfigSettingsWidget() {
        try {
            const response = await fetch('/api/widgets/config/settings');
            if (!response.ok) throw new Error('Failed to load config settings widget');
            return await response.text();
        } catch (error) {
            console.error('Error loading config settings widget:', error);
            return `<div class="error">Fehler beim Laden der System-Einstellungen: ${error.message}</div>`;
        }
    }

    /**
     * Injiziert das Config Settings Widget in die Config-Seite
     */
    async function injectConfigSettingsWidget() {
        const targetContainer = document.querySelector('#config-settings-container');
        if (!targetContainer) {
            console.warn('Config settings container not found');
            return;
        }

        const widgetHtml = await loadConfigSettingsWidget();
        targetContainer.innerHTML = widgetHtml;
        
        // Event Listener registrieren
        setupEventListeners();
    }

    /**
     * Registriert alle Event Listener für das Config Settings Widget
     */
    function setupEventListeners() {
        // Output Dir - Auto-Save bei Blur
        const outputDirField = document.getElementById('output_dir');
        if (outputDirField) {
            outputDirField.addEventListener('blur', function() {
                // Nutzt die zentrale handleFieldChange Funktion aus settings.js
                if (window.handleFieldChange) {
                    window.handleFieldChange({ target: outputDirField });
                }
            });
        }
    }

    /**
     * Directory Browser Functions
     */
    window.openDirectoryBrowser = function() {
        const currentOutputDir = document.getElementById('output_dir')?.value || '/';
        loadDirectories(currentOutputDir);
        
        const modal = document.getElementById('directoryBrowserModal');
        if (modal) {
            modal.style.display = 'block';
        }
    };

    window.closeDirectoryBrowser = function() {
        const modal = document.getElementById('directoryBrowserModal');
        if (modal) {
            modal.style.display = 'none';
        }
    };

    function loadDirectories(path) {
        currentBrowserPath = path;
        
        fetch('/api/browse_directories', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ path: path })
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                renderDirectoryList(data.current_path, data.directories, data.writable);
            } else {
                if (window.showMessage) {
                    window.showMessage(`Fehler: ${data.message}`, 'error');
                }
            }
        })
        .catch(error => {
            if (window.showMessage) {
                window.showMessage(`Fehler beim Laden der Verzeichnisse: ${error.message}`, 'error');
            }
        });
    }

    function renderDirectoryList(currentPath, directories, writable) {
        const pathDisplay = document.getElementById('currentPath');
        const dirList = document.getElementById('directoryList');
        
        if (pathDisplay) {
            pathDisplay.textContent = currentPath;
        }
        
        if (dirList) {
            dirList.innerHTML = '';
            
            // Parent directory (..)
            if (currentPath !== '/') {
                const parentItem = document.createElement('div');
                parentItem.className = 'directory-item';
                parentItem.innerHTML = '<span class="dir-icon">📁</span><span class="dir-name">..</span>';
                parentItem.onclick = () => {
                    const parentPath = currentPath.split('/').slice(0, -1).join('/') || '/';
                    loadDirectories(parentPath);
                };
                dirList.appendChild(parentItem);
            }
            
            // Subdirectories
            directories.forEach(dir => {
                const dirItem = document.createElement('div');
                dirItem.className = 'directory-item';
                dirItem.innerHTML = `<span class="dir-icon">📁</span><span class="dir-name">${dir}</span>`;
                dirItem.onclick = () => {
                    const newPath = currentPath === '/' ? `/${dir}` : `${currentPath}/${dir}`;
                    loadDirectories(newPath);
                };
                dirList.appendChild(dirItem);
            });
            
            // Writable indicator
            if (!writable) {
                const warningDiv = document.createElement('div');
                warningDiv.className = 'directory-warning';
                warningDiv.innerHTML = '⚠️ Dieser Ordner ist nicht beschreibbar';
                dirList.appendChild(warningDiv);
            }
        }
    }

    window.selectCurrentDirectory = function() {
        const outputDirField = document.getElementById('output_dir');
        if (!outputDirField) return;
        
        outputDirField.value = currentBrowserPath;
        
        // Auto-Save: Trigger blur event to save immediately
        outputDirField.dispatchEvent(new Event('blur'));
        
        closeDirectoryBrowser();
    };

    // Auto-Injection beim Laden der Settings-Seite
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', injectConfigSettingsWidget);
    } else {
        injectConfigSettingsWidget();
    }

})();
