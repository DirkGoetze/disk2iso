#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
============================================================================
disk2iso - Metadata Widget Settings Route
============================================================================
Filepath: www/routes/widgets/metadata_widget_settings.py

Beschreibung:
    Flask Blueprint für Metadata Framework Einstellungs-Widget
    - Lädt Metadata-Konfiguration aus libmetadata.ini
    - Liefert HTML-Template und Config-Daten an Frontend
============================================================================
"""

from flask import Blueprint, jsonify, render_template
import subprocess
import os

# Blueprint erstellen
metadata_widget_settings_bp = Blueprint(
    'metadata_widget_settings',
    __name__,
    url_prefix='/api/widgets/metadata'
)

# Pfade
INSTALL_DIR = os.environ.get('DISK2ISO_INSTALL_DIR', '/opt/disk2iso')
CONFIG_INI = os.path.join(INSTALL_DIR, 'conf/libmetadata.ini')


def get_metadata_config():
    """
    Liest Metadata-Konfiguration aus libmetadata.ini
    
    Returns:
        dict: Konfigurationswerte
    """
    config = {
        'METADATA_SELECTION_TIMEOUT': 60,
        'METADATA_CACHE_ENABLED': 'true',
        'METADATA_CHECK_INTERVAL': 1,
        'METADATA_DEFAULT_APPLY_FUNC': 'metadata_default_apply'
    }
    
    try:
        # Bash-Script zum Lesen der INI-Werte
        script = f"""
source {INSTALL_DIR}/lib/libsettings.sh

# Lese Framework-Werte aus INI
TIMEOUT=$(config_get_value_ini "metadata" "framework" "selection_timeout" "60")
CACHE=$(config_get_value_ini "metadata" "framework" "cache_enabled" "true")
INTERVAL=$(config_get_value_ini "metadata" "framework" "check_interval" "1")
APPLY_FUNC=$(config_get_value_ini "metadata" "framework" "default_apply_func" "metadata_default_apply")

# Ausgabe als Key=Value
echo "METADATA_SELECTION_TIMEOUT=$TIMEOUT"
echo "METADATA_CACHE_ENABLED=$CACHE"
echo "METADATA_CHECK_INTERVAL=$INTERVAL"
echo "METADATA_DEFAULT_APPLY_FUNC=$APPLY_FUNC"
        """
        
        result = subprocess.run(
            ['bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            # Parse Output
            for line in result.stdout.strip().split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    # Konvertiere numerische Werte
                    if key in ['METADATA_SELECTION_TIMEOUT', 'METADATA_CHECK_INTERVAL']:
                        try:
                            config[key] = int(value)
                        except ValueError:
                            pass  # Behalte Default
                    else:
                        config[key] = value
    
    except Exception as e:
        print(f"Fehler beim Lesen der Metadata-Config: {e}")
    
    return config


@metadata_widget_settings_bp.route('/settings', methods=['GET'])
def get_metadata_settings_widget():
    """
    API-Endpoint: Liefert Metadata Settings Widget HTML + Config
    
    Returns:
        JSON: {
            'html': str,      # Widget HTML
            'config': dict    # Aktuelle Konfiguration
        }
    """
    try:
        # Lade Config
        config = get_metadata_config()
        
        # Rendere Template
        html = render_template('widgets/metadata_widget_settings.html')
        
        return jsonify({
            'success': True,
            'html': html,
            'config': config
        })
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def register_blueprint(app):
    """
    Registriert Blueprint in Flask App
    
    Args:
        app: Flask Application Instanz
    """
    app.register_blueprint(metadata_widget_settings_bp)
