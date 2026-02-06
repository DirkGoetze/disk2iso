#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
disk2iso - Outputdir Widget (2x1) - Systeminfo
============================================================================
Filepath: www/routes/widgets/outputdir_systeminfo.py

Beschreibung:
    Flask Blueprint für Output-Directory-Widget
    - Zeigt Speicherplatz-Informationen des Ausgabeverzeichnisses
    - Nutzt systeminfo_get_storage_info() aus libsysteminfo.sh
============================================================================
"""

from flask import Blueprint, jsonify
import subprocess
import json
import os
from datetime import datetime

# Blueprint erstellen
outputdir_systeminfo_bp = Blueprint(
    'outputdir_systeminfo',
    __name__,
    url_prefix='/api/widgets/systeminfo'
)

# Pfade
INSTALL_DIR = os.environ.get('DISK2ISO_INSTALL_DIR', '/opt/disk2iso')


def get_storage_info():
    """
    Ruft Speicherplatz-Informationen via Bash-Funktion ab
    Nutzt systeminfo_get_storage_info() aus libsysteminfo.sh
    """
    try:
        result = subprocess.run(
            ['bash', '-c', f'source {INSTALL_DIR}/lib/libsysteminfo.sh && source {INSTALL_DIR}/lib/libfolders.sh && systeminfo_get_storage_info'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return json.loads(result.stdout.strip())
        return {}
    except Exception as e:
        print(f"Fehler beim Abrufen von Speicherplatz-Informationen: {e}")
        return {}


@outputdir_systeminfo_bp.route('/outputdir')
def api_outputdir():
    """
    GET /api/widgets/systeminfo/outputdir
    Liefert Speicherplatz-Informationen des Output-Verzeichnisses
    """
    storage_info = get_storage_info()
    
    # JavaScript erwartet data.output_dir und data.disk_space
    return jsonify({
        'success': True,
        'output_dir': storage_info.get('path', '/media/iso'),
        'disk_space': {
            'free_gb': storage_info.get('free_gb', '0'),
            'total_gb': storage_info.get('total_gb', '0'),
            'used_percent': storage_info.get('used_percent', 0),
            'free_percent': storage_info.get('free_percent', 100)
        },
        'timestamp': datetime.now().isoformat()
    })


def register_blueprint(app):
    """Registriert Blueprint in Flask-App"""
    app.register_blueprint(outputdir_systeminfo_bp)
