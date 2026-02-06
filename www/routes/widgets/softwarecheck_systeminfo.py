#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
disk2iso - Softwarecheck Widget (2x1) - Systeminfo
============================================================================
Filepath: www/routes/widgets/softwarecheck_systeminfo.py

Beschreibung:
    Flask Blueprint für Software-Check-Widget
    - Kompakte Übersicht: Alle Dependencies aktuell ✅ oder Updates verfügbar ⚠️
    - Nutzt systeminfo_get_software_info() aus libsysteminfo.sh
============================================================================
"""

from flask import Blueprint, jsonify
import subprocess
import json
import os
from datetime import datetime

# Blueprint erstellen
softwarecheck_systeminfo_bp = Blueprint(
    'softwarecheck_systeminfo',
    __name__,
    url_prefix='/api/widgets/systeminfo'
)

# Pfade
INSTALL_DIR = os.environ.get('DISK2ISO_INSTALL_DIR', '/opt/disk2iso')


def get_software_info():
    """
    Ruft Software-Informationen via Bash-Funktion ab
    Nutzt systeminfo_get_software_info() aus libsysteminfo.sh
    """
    try:
        result = subprocess.run(
            ['bash', '-c', f'source {INSTALL_DIR}/lib/libsysteminfo.sh && systeminfo_get_software_info'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return json.loads(result.stdout.strip())
        return {}
    except Exception as e:
        print(f"Fehler beim Abrufen von Software-Informationen: {e}")
        return {}


@softwarecheck_systeminfo_bp.route('/softwarecheck')
def api_softwarecheck():
    """
    GET /api/widgets/systeminfo/softwarecheck
    Liefert Software-Liste (JavaScript berechnet Status selbst)
    """
    software_info = get_software_info()
    
    # Konvertiere Dictionary in flache Liste für JavaScript
    software_list = []
    for category, tools in software_info.items():
        if isinstance(tools, list):
            software_list.extend(tools)
    
    return jsonify({
        'success': True,
        'software': software_list,  # JavaScript erwartet data.software (Liste)
        'timestamp': datetime.now().isoformat()
    })


def register_blueprint(app):
    """Registriert Blueprint in Flask-App"""
    app.register_blueprint(softwarecheck_systeminfo_bp)
