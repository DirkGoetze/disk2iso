/**
 * disk2iso Module Loader
 * Lädt JavaScript-Module dynamisch basierend auf Backend-Konfiguration
 * 
 * Workflow:
 * 1. Fragt /api/modules ab (welche Module sind aktiviert?)
 * 2. Lädt nur JS-Dateien für aktivierte Module
 * 3. Ruft init-Funktionen der Module auf
 */

(function() {
    'use strict';
    
    // Modul-Definitionen: Mapping von Modul-Namen zu JS-Dateien
    const MODULE_DEFINITIONS = {
        'metadata': {
            files: ['musicbrainz.js', 'tmdb.js'],
            init: function() {
                // Initialisiere Metadata-UI falls vorhanden
                if (typeof initMusicBrainzModal === 'function') {
                    initMusicBrainzModal();
                }
                if (typeof initTmdbModal === 'function') {
                    initTmdbModal();
                }
            }
        },
        'cd': {
            files: [],  // CD-spezifische JS (falls später benötigt)
            init: null
        },
        'dvd': {
            files: [],  // DVD-spezifische JS (falls später benötigt)
            init: null
        },
        'bluray': {
            files: [],  // Bluray-spezifische JS (falls später benötigt)
            init: null
        },
        'mqtt': {
            files: ['widgets/status_3x4_mqtt.js'],  // MQTT Widget Loader (3x4)
            init: function() {
                // MQTT initialisiert sich selbst
                if (typeof window.mqtt !== 'undefined' && typeof window.mqtt.init === 'function') {
                    window.mqtt.init();
                }
            }
        }
    };
    
    // Bereits geladene Scripts tracken (verhindert Doppel-Loading)
    const loadedScripts = new Set();
    
    /**
     * Lädt ein einzelnes Script dynamisch
     * @param {string} src - Script-Pfad (relativ zu /static/js/)
     * @returns {Promise} Promise das resolved wenn Script geladen ist
     */
    function loadScript(src) {
        return new Promise((resolve, reject) => {
            // Bereits geladen?
            if (loadedScripts.has(src)) {
                resolve();
                return;
            }
            
            const script = document.createElement('script');
            script.src = `/static/js/${src}?v=${Date.now()}`;  // Cache-Bust
            script.async = true;
            
            script.onload = () => {
                loadedScripts.add(src);
                console.log(`[ModuleLoader] Geladen: ${src}`);
                resolve();
            };
            
            script.onerror = () => {
                console.error(`[ModuleLoader] Fehler beim Laden: ${src}`);
                reject(new Error(`Failed to load script: ${src}`));
            };
            
            document.body.appendChild(script);
        });
    }
    
    /**
     * Lädt alle Scripts für ein Modul
     * @param {string} moduleName - Name des Moduls
     * @param {object} moduleConfig - Modul-Konfiguration
     * @returns {Promise} Promise das resolved wenn alle Scripts geladen sind
     */
    async function loadModule(moduleName, moduleConfig) {
        if (!moduleConfig.files || moduleConfig.files.length === 0) {
            return;  // Kein JS für dieses Modul
        }
        
        console.log(`[ModuleLoader] Lade Modul: ${moduleName}`);
        
        try {
            // Lade alle Scripts parallel
            await Promise.all(
                moduleConfig.files.map(file => loadScript(file))
            );
            
            // Rufe Init-Funktion auf (falls vorhanden)
            if (typeof moduleConfig.init === 'function') {
                moduleConfig.init();
            }
            
            console.log(`[ModuleLoader] Modul geladen: ${moduleName}`);
        } catch (error) {
            console.error(`[ModuleLoader] Fehler beim Laden von ${moduleName}:`, error);
        }
    }
    
    /**
     * Fragt Backend nach aktivierten Modulen und lädt diese
     */
    async function initializeModules() {
        try {
            const response = await fetch('/api/modules');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            const data = await response.json();
            const enabledModules = data.enabled_modules || {};
            
            console.log('[ModuleLoader] Aktivierte Module:', enabledModules);
            
            // Lade nur aktivierte Module
            const loadPromises = [];
            
            for (const [moduleName, isEnabled] of Object.entries(enabledModules)) {
                if (isEnabled && MODULE_DEFINITIONS[moduleName]) {
                    loadPromises.push(
                        loadModule(moduleName, MODULE_DEFINITIONS[moduleName])
                    );
                } else if (isEnabled) {
                    console.warn(`[ModuleLoader] Unbekanntes Modul: ${moduleName}`);
                }
            }
            
            // Warte bis alle Module geladen sind
            await Promise.all(loadPromises);
            
            console.log('[ModuleLoader] Alle Module geladen');
            
            // Dispatche Custom Event für andere Scripts
            document.dispatchEvent(new CustomEvent('modulesLoaded', {
                detail: { enabledModules }
            }));
            
        } catch (error) {
            console.error('[ModuleLoader] Fehler beim Laden der Modul-Konfiguration:', error);
            
            // Fallback: Lade kritische Module trotzdem
            console.warn('[ModuleLoader] Fallback: Lade kritische Module');
            await loadModule('metadata', MODULE_DEFINITIONS.metadata);
        }
    }
    
    /**
     * Prüft ob ein Modul geladen ist
     * @param {string} moduleName - Name des Moduls
     * @returns {boolean} True wenn Modul geladen wurde
     */
    window.isModuleLoaded = function(moduleName) {
        const moduleConfig = MODULE_DEFINITIONS[moduleName];
        if (!moduleConfig || !moduleConfig.files) {
            return false;
        }
        
        // Prüfe ob alle Scripts des Moduls geladen wurden
        return moduleConfig.files.every(file => loadedScripts.has(file));
    };
    
    // Starte Loading sobald DOM bereit ist
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initializeModules);
    } else {
        // DOM bereits geladen (z.B. bei dynamischem Script-Inject)
        initializeModules();
    }
})();
