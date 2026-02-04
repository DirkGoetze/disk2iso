#!/usr/bin/env python3
"""
Configuration Management Routes
Provides field-by-field config operations for core settings
"""

from flask import Blueprint, jsonify, request, g
import subprocess
import json
from pathlib import Path

config_bp = Blueprint('config', __name__, url_prefix='/api/config')

INSTALL_DIR = Path("/opt/disk2iso")
CONFIG_HANDLERS = {
    "DEFAULT_OUTPUT_DIR": "disk2iso",
    "DDRESCUE_RETRIES": "none",
    "USB_DRIVE_DETECTION_ATTEMPTS": "none", 
    "USB_DRIVE_DETECTION_DELAY": "none"
}

@config_bp.route('/<key>', methods=['GET'])
def get_config_value(key):
    """
    Liest einzelnen Config-Wert aus disk2iso.conf
    
    GET /api/config/DEFAULT_OUTPUT_DIR
    Response: {"success": true, "value": "/media/iso"}
    """
    # Validierung: Nur bekannte Keys erlauben
    if key not in CONFIG_HANDLERS:
        return jsonify({
            'success': False, 
            'message': f'Unknown config key: {key}'
        }), 400
    
    try:
        script = f"""
        source {INSTALL_DIR}/lib/libconfig.sh
        get_config_value "{key}"
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
        
        # Parse JSON response from shell
        try:
            data = json.loads(result.stdout.strip())
            return jsonify(data), 200
        except json.JSONDecodeError:
            return jsonify({
                'success': False,
                'message': 'Invalid JSON response from shell'
            }), 500
            
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
    if key not in CONFIG_HANDLERS:
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
        
        script = f"""
        source {INSTALL_DIR}/lib/libconfig.sh
        update_config_value "{key}" '{value_escaped}'
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
        
        # Parse JSON response
        try:
            response_data = json.loads(result.stdout.strip())
            
            # Check ob Service-Restart erforderlich ist
            restart_service = CONFIG_HANDLERS[key]
            if restart_service != "none":
                # Trigger restart
                restart_result = subprocess.run(
                    ['/bin/bash', '-c', f'source {INSTALL_DIR}/lib/libconfig.sh; restart_service "{restart_service}"'],
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
            
        except json.JSONDecodeError:
            return jsonify({
                'success': False,
                'message': 'Invalid JSON response from shell'
            }), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'Timeout'}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@config_bp.route('/all', methods=['GET'])
def get_all_config_values():
    """
    Legacy: Liest alle Config-Werte auf einmal (Batch)
    DEPRECATED: Für neue Implementierungen field-by-field nutzen
    
    GET /api/config/all
    Response: {"success": true, "output_dir": "...", "ddrescue_retries": 3, ...}
    """
    try:
        script = f"""
        source {INSTALL_DIR}/lib/libconfig.sh
        get_all_config_values
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
                'message': 'Error reading all config values'
            }), 500
        
        try:
            data = json.loads(result.stdout.strip())
            return jsonify(data), 200
        except json.JSONDecodeError:
            return jsonify({
                'success': False,
                'message': 'Invalid JSON response from shell'
            }), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'Timeout'}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500
