"""
disk2iso - Config Widget Settings Routes
Stellt die System-Einstellungen bereit (Output Dir, Sprache)
"""

import os
import sys
from flask import Blueprint, render_template, jsonify, request
from i18n import t

# Blueprint für Config Settings Widget
config_settings_bp = Blueprint('config_settings', __name__)

def get_config_settings():
    """
    Liest die Config-Einstellungen aus der Konfigurationsdatei
    Analog zu get_mqtt_config() in routes_mqtt.py
    """
    try:
        # Lese output_dir aus config.sh
        config_sh = '/opt/disk2iso/conf/config.sh'
        
        config = {
            "output_dir": "/media/iso",  # Default
        }
        
        if os.path.exists(config_sh):
            with open(config_sh, 'r') as f:
                for line in f:
                    line = line.strip()
                    
                    # DEFAULT_OUTPUT_DIR
                    if line.startswith('DEFAULT_OUTPUT_DIR='):
                        value = line.split('=', 1)[1].strip('"').strip("'")
                        config['output_dir'] = value
        
        return config
        
    except Exception as e:
        print(f"Fehler beim Lesen der Config-Einstellungen: {e}", file=sys.stderr)
        return {
            "output_dir": "/media/iso",
        }


@config_settings_bp.route('/api/widgets/config/settings')
def api_config_settings_widget():
    """
    Rendert das Config Settings Widget
    Zeigt System-Einstellungen (Output Dir, Sprache)
    """
    config = get_config_settings()
    
    # Rendere Widget-Template
    return render_template('widgets/config_widget_settings.html',
                         config=config,
                         t=t)


@config_settings_bp.route('/api/browse_directories', methods=['POST'])
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
