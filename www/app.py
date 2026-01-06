#!/usr/bin/env python3
"""
disk2iso Web Interface
Version: 1.2.0
Description: Flask-basierte Web-Oberfläche für disk2iso Monitoring
"""

from flask import Flask, render_template, jsonify, request
import os
import sys
import json
import subprocess
from datetime import datetime
from pathlib import Path

app = Flask(__name__)

# Konfiguration
INSTALL_DIR = Path("/opt/disk2iso")
CONFIG_FILE = INSTALL_DIR / "lib" / "config.sh"
VERSION_FILE = INSTALL_DIR / "VERSION"

def get_version():
    """Liest Version aus VERSION-Datei"""
    try:
        if VERSION_FILE.exists():
            return VERSION_FILE.read_text().strip()
    except:
        pass
    return "1.2.0"

def get_config():
    """Liest Konfiguration aus config.sh"""
    config = {
        "output_dir": "/media/iso",
        "mqtt_enabled": False,
        "mqtt_broker": "",
    }
    
    try:
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('DEFAULT_OUTPUT_DIR='):
                        config['output_dir'] = line.split('=', 1)[1].strip('"')
                    elif line.startswith('MQTT_ENABLED='):
                        config['mqtt_enabled'] = 'true' in line.lower()
                    elif line.startswith('MQTT_BROKER='):
                        config['mqtt_broker'] = line.split('=', 1)[1].strip('"')
    except Exception as e:
        print(f"Fehler beim Lesen der Konfiguration: {e}", file=sys.stderr)
    
    return config

def get_service_status():
    """Prüft Status des disk2iso Service"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'disk2iso'],
            capture_output=True,
            text=True,
            timeout=2
        )
        return result.stdout.strip() == 'active'
    except:
        return False

def get_disk_space(path):
    """Ermittelt freien Speicherplatz"""
    try:
        stat = os.statvfs(path)
        free_gb = (stat.f_bavail * stat.f_frsize) / (1024**3)
        total_gb = (stat.f_blocks * stat.f_frsize) / (1024**3)
        used_percent = ((total_gb - free_gb) / total_gb * 100) if total_gb > 0 else 0
        return {
            'free_gb': round(free_gb, 2),
            'total_gb': round(total_gb, 2),
            'used_percent': round(used_percent, 1)
        }
    except:
        return {'free_gb': 0, 'total_gb': 0, 'used_percent': 0}

def count_iso_files(path):
    """Zählt ISO-Dateien im Ausgabeverzeichnis"""
    try:
        if not os.path.exists(path):
            return 0
        count = 0
        for root, dirs, files in os.walk(path):
            count += len([f for f in files if f.lower().endswith('.iso')])
        return count
    except:
        return 0

# Routes
@app.route('/')
def index():
    """Haupt-Status-Seite"""
    config = get_config()
    version = get_version()
    service_running = get_service_status()
    disk_space = get_disk_space(config['output_dir'])
    iso_count = count_iso_files(config['output_dir'])
    
    return render_template('index.html',
        version=version,
        service_running=service_running,
        config=config,
        disk_space=disk_space,
        iso_count=iso_count,
        current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    )

@app.route('/api/status')
def api_status():
    """API-Endpoint für Status-Abfrage"""
    config = get_config()
    
    return jsonify({
        'version': get_version(),
        'service_running': get_service_status(),
        'output_dir': config['output_dir'],
        'mqtt_enabled': config['mqtt_enabled'],
        'mqtt_broker': config['mqtt_broker'],
        'disk_space': get_disk_space(config['output_dir']),
        'iso_count': count_iso_files(config['output_dir']),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/health')
def health():
    """Health-Check Endpoint"""
    return jsonify({'status': 'ok', 'version': get_version()})

# Error Handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    # Nur für Entwicklung - In Produktion wird Gunicorn/Flask Server verwendet
    app.run(host='0.0.0.0', port=8080, debug=False)
