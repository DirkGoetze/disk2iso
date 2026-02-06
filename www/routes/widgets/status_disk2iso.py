#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
disk2iso - Status Widget (2x1) - Disk2iso
============================================================================
Filepath: www/routes/widgets/status_disk2iso.py

Beschreibung:
    Flask Blueprint für disk2iso Service Status Widget
    - Zeigt Status des disk2iso Hintergrund-Service
    - Ermöglicht Service-Neustart
============================================================================
"""

from flask import Blueprint, jsonify
import subprocess
import json
import os
from datetime import datetime

# Blueprint erstellen
status_disk2iso_bp = Blueprint(
    'status_disk2iso',
    __name__,
    url_prefix='/api/widgets/disk2iso'
)

# Pfade
INSTALL_DIR = os.environ.get('DISK2ISO_INSTALL_DIR', '/opt/disk2iso')


def get_disk2iso_service_status():
    """
    Ruft Status des disk2iso Service ab
    Nutzt service_get_status() aus libservice.sh
    """
    try:
        result = subprocess.run(
            ['bash', '-c', f'source {INSTALL_DIR}/lib/liblogging.sh && source {INSTALL_DIR}/lib/libfolders.sh && source {INSTALL_DIR}/lib/libsettings.sh && source {INSTALL_DIR}/lib/libservice.sh && service_get_status "disk2iso"'],
            capture_output=True, text=True, timeout=5
        )
        
        if result.returncode == 0:
            return json.loads(result.stdout.strip())
        return {
            'status': 'unknown',
            'running': False,
            'enabled': False
        }
    except Exception as e:
        print(f"Fehler beim Abrufen des disk2iso Service-Status: {e}")
        return {
            'status': 'error',
            'running': False,
            'enabled': False,
            'error': str(e)
        }


@status_disk2iso_bp.route('/status')
def api_disk2iso_status():
    """
    GET /api/widgets/disk2iso/status
    Liefert aktuellen Status des disk2iso Service
    """
    service_status = get_disk2iso_service_status()
    
    return jsonify({
        'success': True,
        'service': 'disk2iso',
        **service_status,
        'timestamp': datetime.now().isoformat()
    })


@status_disk2iso_bp.route('/restart', methods=['POST'])
def api_disk2iso_restart():
    """
    POST /api/widgets/disk2iso/restart
    Startet disk2iso Service neu
    """
    try:
        result = subprocess.run(
            ['bash', '-c', f'source {INSTALL_DIR}/lib/liblogging.sh && source {INSTALL_DIR}/lib/libservice.sh && service_restart "disk2iso"'],
            capture_output=True, text=True, timeout=10
        )
        
        if result.returncode == 0:
            return jsonify({
                'success': True,
                'message': 'disk2iso Service erfolgreich neu gestartet',
                'timestamp': datetime.now().isoformat()
            })
        else:
            return jsonify({
                'success': False,
                'message': 'Fehler beim Neustart von disk2iso',
                'error': result.stderr,
                'timestamp': datetime.now().isoformat()
            }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500


def register_blueprint(app):
    """Registriert Blueprint in Flask-App"""
    app.register_blueprint(status_disk2iso_bp)
