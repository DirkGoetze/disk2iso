#!/usr/bin/env python3
"""
Configuration Management Routes
Provides field-by-field config operations for core settings
Uses config_get_value_conf() and config_set_value_conf() directly
"""

from flask import Blueprint, jsonify, request, g
import subprocess
import json
from pathlib import Path

config_bp = Blueprint('config', __name__, url_prefix='/api/config')

INSTALL_DIR = Path("/opt/disk2iso")

# Config Keys die über diese API verwaltet werden (Core Settings aus disk2iso.conf)
ALLOWED_KEYS = [
    "DEFAULT_OUTPUT_DIR",
    "DDRESCUE_RETRIES",
    "USB_DRIVE_DETECTION_ATTEMPTS",
    "USB_DRIVE_DETECTION_DELAY"
]

# Keys die einen Service-Neustart erfordern
RESTART_REQUIRED_KEYS = {
    "DEFAULT_OUTPUT_DIR": "disk2iso"
}

@config_bp.route('/<key>', methods=['GET'])
def get_config_value(key):
    """
    Liest einzelnen Config-Wert aus disk2iso.conf
    
    GET /api/config/DEFAULT_OUTPUT_DIR
    Response: {"success": true, "value": "/media/iso"}
    """
    # Validierung: Nur bekannte Keys erlauben
    if key not in ALLOWED_KEYS:
        return jsonify({
            'success': False, 
            'message': f'Unknown config key: {key}'
        }), 400
    
    try:
        # Nutze config_get_value_conf() direkt (kein Legacy-Wrapper)
        script = f"""
        source {INSTALL_DIR}/lib/libsettings.sh
        config_get_value_conf "disk2iso" "{key}"
        """
        
        result = subprocess.run(
            ['/bin/bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            return jsonify({
                'success': False,
                'message': f'Error reading config key: {key}'
            }), 500
        
        # config_get_value_conf() gibt nur den Wert zurück (kein JSON)
        value = result.stdout.strip()
        return jsonify({'success': True, 'value': value}), 200
            
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'Timeout'}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@config_bp.route('/<key>', methods=['PUT'])
def set_config_value(key):
    """
    Schreibt einzelnen Config-Wert in disk2iso.conf
    Optional: Triggert Service-Restart wenn erforderlich
    
    PUT /api/config/DEFAULT_OUTPUT_DIR
    Body: {"value": "/new/path"}
    Response: {"success": true, "restart_required": false}
    """
    # Validierung: Nur bekannte Keys erlauben
    if key not in ALLOWED_KEYS:
        return jsonify({
            'success': False,
            'message': f'Unknown config key: {key}'
        }), 400
    
    # Hole Value aus Request
    data = request.get_json()
    if not data or 'value' not in data:
        return jsonify({
            'success': False,
            'message': 'Missing "value" in request body'
        }), 400
    
    value = str(data['value'])
    
    try:
        # Escape value for shell
        value_escaped = value.replace("'", "'\\''")
        
        # Nutze config_set_value_conf() direkt
        script = f"""
        source {INSTALL_DIR}/lib/libsettings.sh
        config_set_value_conf "disk2iso" "{key}" '{value_escaped}'
        """
        
        result = subprocess.run(
            ['/bin/bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode != 0:
            return jsonify({
                'success': False,
                'message': f'Error writing config key: {key}'
            }), 500
        
        response_data = {'success': True}
        
        # Check ob Service-Restart erforderlich ist
        if key in RESTART_REQUIRED_KEYS:
            restart_service = RESTART_REQUIRED_KEYS[key]
            
            # Trigger restart via systemctl
            restart_result = subprocess.run(
                ['/usr/bin/systemctl', 'restart', restart_service],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if restart_result.returncode == 0:
                response_data['restart_required'] = True
                response_data['restart_service'] = restart_service
            else:
                response_data['restart_required'] = True
                response_data['restart_failed'] = True
        else:
            response_data['restart_required'] = False
        
        return jsonify(response_data), 200
            
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'Timeout'}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@config_bp.route('/all', methods=['GET'])
def get_all_config_values():
    """
    Legacy: Liest alle Core-Config-Werte auf einmal (Batch)
    DEPRECATED: Für neue Implementierungen field-by-field nutzen
    
    GET /api/config/all
    Response: {"success": true, "DEFAULT_OUTPUT_DIR": "...", "DDRESCUE_RETRIES": 3, ...}
    """
    try:
        response_data = {'success': True}
        
        # Lese alle Core-Settings einzeln (field-by-field)
        for key in ALLOWED_KEYS:
            script = f"""
            source {INSTALL_DIR}/lib/libsettings.sh
            config_get_value_conf "disk2iso" "{key}"
            """
            
            result = subprocess.run(
                ['/bin/bash', '-c', script],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode == 0:
                response_data[key] = result.stdout.strip()
            else:
                response_data[key] = None
        
        return jsonify(response_data), 200
            
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'Timeout'}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500
