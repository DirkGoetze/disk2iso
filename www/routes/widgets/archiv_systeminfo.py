#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
disk2iso - Archiv Widget (2x1) - Systeminfo
============================================================================
Filepath: www/routes/widgets/archiv_systeminfo.py

Beschreibung:
    Flask Blueprint für Archiv-Statistik-Widget
    - Zeigt Anzahl archivierter Medien nach Typ (Audio, DVD, Bluray, Data)
    - Nutzt systeminfo_get_archiv_info() aus libsysteminfo.sh
============================================================================
"""

from flask import Blueprint, jsonify
import subprocess
import json
import os
from datetime import datetime

# Blueprint erstellen
archiv_systeminfo_bp = Blueprint(
    'archiv_systeminfo',
    __name__,
    url_prefix='/api/widgets/systeminfo'
)

# Pfade
INSTALL_DIR = os.environ.get('DISK2ISO_INSTALL_DIR', '/opt/disk2iso')


def get_archiv_info():
    """
    Ruft Archiv-Informationen via Bash-Funktion ab
    Nutzt systeminfo_get_archiv_info() aus libsysteminfo.sh
    """
    try:
        result = subprocess.run(
            ['bash', '-c', f'source {INSTALL_DIR}/lib/libsysteminfo.sh && source {INSTALL_DIR}/lib/libfolders.sh && systeminfo_get_archiv_info'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return json.loads(result.stdout.strip())
        return {}
    except Exception as e:
        print(f"Fehler beim Abrufen von Archiv-Informationen: {e}")
        return {}


@archiv_systeminfo_bp.route('/archiv')
def api_archiv():
    """
    GET /api/widgets/systeminfo/archiv
    Liefert Archiv-Statistiken (Anzahl ISOs pro Typ)
    """
    archiv_info = get_archiv_info()
    
    return jsonify({
        'success': True,
        'archive_counts': archiv_info,  # JavaScript erwartet data.archive_counts
        'timestamp': datetime.now().isoformat()
    })


def register_blueprint(app):
    """Registriert Blueprint in Flask-App"""
    app.register_blueprint(archiv_systeminfo_bp)
