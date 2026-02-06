"""
============================================================================
disk2iso - Settings Widget - Config
============================================================================
Filepath: www/routes/widgets/settings_config.py

Beschreibung:
    Flask Blueprint für Config Settings Widget
    - System-Einstellungen (Output Dir, Sprache)
============================================================================
"""

import os
import sys
from flask import Blueprint, render_template, jsonify, request
from i18n import t

# Blueprint für Config Settings Widget
settings_config_bp = Blueprint('settings_config', __name__)

def get_config_settings():
    """
    Liest Config-Einstellungen via libsettings.sh (BASH)
    Python = Middleware ONLY - keine direkten File-Zugriffe!
    """
    try:
        import subprocess
        
        # Rufe libsettings.sh auf (Architektur-konform)
        script = """
        source /opt/disk2iso/lib/libsettings.sh
        settings_get_value_conf "disk2iso" "DEFAULT_OUTPUT_DIR" "/media/iso"
        """
        
        result = subprocess.run(
            ['/bin/bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=2
        )
        
        output_dir = "/media/iso"  # Default
        if result.returncode == 0 and result.stdout.strip():
            output_dir = result.stdout.strip()
        
        return {
            "output_dir": output_dir,
        }
        
    except Exception as e:
        print(f"Fehler beim Lesen der Config-Einstellungen: {e}", file=sys.stderr)
        return {
            "output_dir": "/media/iso",
        }


@settings_bp.route('/api/widgets/config/settings')
def api_config_settings_widget():
    """
    Rendert das Config Settings Widget
    Zeigt System-Einstellungen (Output Dir, Sprache)
    """
    settings = get_config_settings()
    
    # Rendere Widget-Template
    return render_template('widgets/settings_4x1_config.html',
                         settings=settings,
                         t=t)


@settings_bp.route('/api/browse_directories', methods=['POST'])
def browse_directories():
    """
    Directory Browser API
    Listet Unterverzeichnisse für den Directory Picker
    """
    try:
        data = request.get_json()
        path = data.get('path', '/')
        
        # Sicherheit: Verhindere Directory Traversal
        path = os.path.abspath(path)
        
        if not os.path.exists(path):
            return jsonify({
                'success': False,
                'message': f'Pfad existiert nicht: {path}'
            }), 404
        
        if not os.path.isdir(path):
            return jsonify({
                'success': False,
                'message': f'Kein Verzeichnis: {path}'
            }), 400
        
        # Liste Unterverzeichnisse
        try:
            entries = os.listdir(path)
            directories = sorted([
                d for d in entries 
                if os.path.isdir(os.path.join(path, d)) and not d.startswith('.')
            ])
        except PermissionError:
            return jsonify({
                'success': False,
                'message': f'Keine Berechtigung: {path}'
            }), 403
        
        # Prüfe Schreibberechtigung
        writable = os.access(path, os.W_OK)
        
        return jsonify({
            'success': True,
            'current_path': path,
            'directories': directories,
            'writable': writable
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Serverfehler: {str(e)}'
        }), 500


