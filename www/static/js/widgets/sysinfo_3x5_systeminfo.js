/**
 * Sysinfo Widget (2x1) - Systeminfo
 * Lädt dynamisch OS-Informationen
 * Version: 1.0.0
 */

function loadSystemInfoWidget() {
    fetch('/api/widgets/systeminfo/sysinfo')
        .then(response => response.json())
        .then(data => {
            if (data.success && data.os) {
                updateSystemInfoWidget(data.os);
            }
        })
        .catch(error => {
            console.error('Fehler beim Laden der Systeminformationen:', error);
        });
}

function updateSystemInfoWidget(osInfo) {
    const distribution = document.getElementById('systeminfo-widget-distribution');
    const version = document.getElementById('systeminfo-widget-version');
    const kernel = document.getElementById('systeminfo-widget-kernel');
    const uptime = document.getElementById('systeminfo-widget-uptime');
    
    if (distribution) distribution.textContent = osInfo.distribution || 'Unbekannt';
    if (version) version.textContent = osInfo.version || 'Unbekannt';
    if (kernel) kernel.textContent = osInfo.kernel || 'Unbekannt';
    if (uptime) uptime.textContent = osInfo.uptime || 'Unbekannt';
}

// Auto-Update alle 30 Sekunden (Systeminfo ändert sich selten)
if (document.getElementById('systeminfo-widget')) {
    loadSystemInfoWidget();
    setInterval(loadSystemInfoWidget, 30000);
}
