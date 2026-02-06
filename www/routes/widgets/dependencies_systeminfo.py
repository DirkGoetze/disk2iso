#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
disk2iso - Dependencies Widget (4x1) - Systeminfo
============================================================================
Filepath: www/routes/widgets/dependencies_systeminfo.py

Beschreibung:
    Flask Blueprint für Core-Dependencies-Widget
    - Zeigt detaillierte Liste aller System-Dependencies
    - Nutzt systeminfo_get_software_info() aus libsysteminfo.sh
============================================================================
"""

from flask import Blueprint, jsonify
import subprocess
import json
import os
from datetime import datetime

# Blueprint erstellen
dependencies_systeminfo_bp = Blueprint(
    'dependencies_systeminfo',
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


@dependencies_systeminfo_bp.route('/dependencies')
def api_dependencies():
    """
    GET /api/widgets/systeminfo/dependencies
    Liefert vollständige Software-Dependencies-Liste
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
    app.register_blueprint(dependencies_systeminfo_bp)
