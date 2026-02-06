/**
 * Outputdir Widget (2x1) - Systeminfo
 * Lädt dynamisch Speicherplatz-Informationen für das Ausgabeverzeichnis
 * Version: 1.0.0
 */

function loadOutputDirWidget() {
    fetch('/api/widgets/systeminfo/outputdir')
        .then(response => response.json())
        .then(data => {
            if (data.success && data.disk_space) {
                updateOutputDirWidget(data.output_dir, data.disk_space);
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden der Output-Dir-Informationen:', error);
        });
}

function updateOutputDirWidget(outputDir, diskSpace) {
    const pathEl = document.getElementById('outputdir-widget-path');
    const freeEl = document.getElementById('outputdir-widget-free');
    const totalEl = document.getElementById('outputdir-widget-total');
    const progressEl = document.getElementById('outputdir-widget-progress');
    const progressBarEl = document.getElementById('outputdir-widget-progress-bar');
    
    if (!pathEl || !freeEl || !totalEl || !progressEl || !progressBarEl) return;
    
    // Aktualisiere Werte
    pathEl.textContent = outputDir || '/media/iso';
    freeEl.textContent = diskSpace.free_gb || '0';
    totalEl.textContent = diskSpace.total_gb || '0';
    
    // Aktualisiere Fortschrittsbalken
    const usedPercent = diskSpace.used_percent || 0;
    const freePercent = diskSpace.free_percent || 100;
    
    progressEl.setAttribute('data-label', `${usedPercent}% belegt`);
    progressBarEl.style.width = `${freePercent}%`;
}

// Auto-Update alle 30 Sekunden (Speicherplatz ändert sich langsam)
if (document.getElementById('systeminfo-outputdir-widget')) {
    loadOutputDirWidget();
    setInterval(loadOutputDirWidget, 30000);
}
