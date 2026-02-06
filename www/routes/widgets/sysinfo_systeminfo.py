#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
disk2iso - Sysinfo Widget (2x1) - Systeminfo
============================================================================
Filepath: www/routes/widgets/sysinfo_systeminfo.py

Beschreibung:
    Flask Blueprint für System-Informations-Widget
    - Zeigt Betriebssystem-Informationen (OS, Kernel, Hardware)
    - Nutzt systeminfo_get_os_info() aus libsysteminfo.sh
============================================================================
"""

from flask import Blueprint, jsonify
import subprocess
import json
import os
from datetime import datetime

# Blueprint erstellen
sysinfo_systeminfo_bp = Blueprint(
    'sysinfo_systeminfo',
    __name__,
    url_prefix='/api/widgets/systeminfo'
)

# Pfade
INSTALL_DIR = os.environ.get('DISK2ISO_INSTALL_DIR', '/opt/disk2iso')


def get_os_info():
    """
    Ruft OS-Informationen via Bash-Funktion ab
    Nutzt systeminfo_get_os_info() aus libsysteminfo.sh
    """
    try:
        result = subprocess.run(
            ['bash', '-c', f'source {INSTALL_DIR}/lib/libsysteminfo.sh && systeminfo_get_os_info'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return json.loads(result.stdout.strip())
        return {}
    except Exception as e:
        print(f"Fehler beim Abrufen von OS-Informationen: {e}")
        return {}


@sysinfo_systeminfo_bp.route('/sysinfo')
def api_sysinfo():
    """
    GET /api/widgets/systeminfo/sysinfo
    Liefert Betriebssystem-Informationen
    """
    os_info = get_os_info()
    
    return jsonify({
        'success': True,
        'os': os_info,  # JavaScript erwartet data.os
        'timestamp': datetime.now().isoformat()
    })


def register_blueprint(app):
    """Registriert Blueprint in Flask-App"""
    app.register_blueprint(sysinfo_systeminfo_bp)
