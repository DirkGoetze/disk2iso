#!/usr/bin/env python3
"""
disk2iso Web Interface
Version: 1.2.0
Description: Flask-basierte Web-Oberfläche für disk2iso Monitoring
"""

from flask import Flask, render_template, jsonify, request, Response
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
API_DIR = INSTALL_DIR / "api"

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
        "mp3_quality": 2,
        "ddrescue_retries": 1,
        "usb_detection_attempts": 5,
        "usb_detection_delay": 10,
        "mqtt_enabled": False,
        "mqtt_broker": "",
        "mqtt_port": 1883,
        "mqtt_user": "",
        "mqtt_password": "",
    }
    
    try:
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('DEFAULT_OUTPUT_DIR='):
                        config['output_dir'] = line.split('=', 1)[1].strip('"')
                    elif line.startswith('MP3_QUALITY='):
                        try:
                            config['mp3_quality'] = int(line.split('=', 1)[1].strip())
                        except:
                            pass
                    elif line.startswith('DDRESCUE_RETRIES='):
                        try:
                            config['ddrescue_retries'] = int(line.split('=', 1)[1].strip())
                        except:
                            pass
                    elif line.startswith('USB_DRIVE_DETECTION_ATTEMPTS='):
                        try:
                            config['usb_detection_attempts'] = int(line.split('=', 1)[1].strip())
                        except:
                            pass
                    elif line.startswith('USB_DRIVE_DETECTION_DELAY='):
                        try:
                            config['usb_detection_delay'] = int(line.split('=', 1)[1].strip())
                        except:
                            pass
                    elif line.startswith('MQTT_ENABLED='):
                        config['mqtt_enabled'] = 'true' in line.lower()
                    elif line.startswith('MQTT_BROKER='):
                        config['mqtt_broker'] = line.split('=', 1)[1].strip('"')
                    elif line.startswith('MQTT_PORT='):
                        try:
                            config['mqtt_port'] = int(line.split('=', 1)[1].strip())
                        except:
                            pass
                    elif line.startswith('MQTT_USER='):
                        config['mqtt_user'] = line.split('=', 1)[1].strip('"')
                    elif line.startswith('MQTT_PASSWORD='):
                        config['mqtt_password'] = line.split('=', 1)[1].strip('"')
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

def get_iso_files_by_type(path):
    """Holt alle ISO-Dateien gruppiert nach Typ"""
    result = {
        'audio': [],
        'dvd': [],
        'bluray': [],
        'data': []
    }
    
    try:
        if not os.path.exists(path):
            return result
        
        for root, dirs, files in os.walk(path):
            for filename in files:
                if not filename.lower().endswith('.iso'):
                    continue
                
                filepath = os.path.join(root, filename)
                try:
                    stat = os.stat(filepath)
                    file_info = {
                        'name': filename,
                        'path': filepath,
                        'size': stat.st_size,
                        'created': datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                        'modified': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
                    }
                    
                    # Determine type based on filename patterns
                    filename_lower = filename.lower()
                    if '_audio-cd_' in filename_lower or '_audiocd_' in filename_lower:
                        result['audio'].append(file_info)
                    elif '_bluray_' in filename_lower or '_bd_' in filename_lower or '_blu-ray_' in filename_lower:
                        result['bluray'].append(file_info)
                    elif '_dvd_' in filename_lower or '_dvd-video_' in filename_lower:
                        result['dvd'].append(file_info)
                    else:
                        result['data'].append(file_info)
                except Exception as e:
                    print(f"Fehler beim Lesen von {filename}: {e}", file=sys.stderr)
        
        # Sort each list by modified date (newest first)
        for type_key in result:
            result[type_key].sort(key=lambda x: x['modified'], reverse=True)
    
    except Exception as e:
        print(f"Fehler beim Durchsuchen des Archivs: {e}", file=sys.stderr)
    
    return result

def read_api_json(filename):
    """Liest JSON-Datei aus API-Verzeichnis"""
    try:
        file_path = API_DIR / filename
        if file_path.exists():
            with open(file_path, 'r') as f:
                return json.load(f)
    except Exception as e:
        print(f"Fehler beim Lesen von {filename}: {e}", file=sys.stderr)
    return None

def get_live_status():
    """Liest Live-Status aus API JSON-Dateien"""
    status = read_api_json('status.json') or {'status': 'idle', 'timestamp': ''}
    attributes = read_api_json('attributes.json') or {
        'disc_label': '',
        'disc_type': '',
        'disc_size_mb': 0,
        'progress_percent': 0,
        'progress_mb': 0,
        'total_mb': 0,
        'eta': '',
        'filename': '',
        'method': 'unknown',
        'container_type': 'none',
        'error_message': None
    }
    progress = read_api_json('progress.json') or {
        'percent': 0,
        'copied_mb': 0,
        'total_mb': 0,
        'eta': '',
        'timestamp': ''
    }
    
    return {
        'status': status.get('status', 'idle'),
        'timestamp': status.get('timestamp', ''),
        'disc_label': attributes.get('disc_label', ''),
        'disc_type': attributes.get('disc_type', ''),
        'disc_size_mb': attributes.get('disc_size_mb', 0),
        'progress_percent': progress.get('percent', 0),
        'progress_mb': progress.get('copied_mb', 0),
        'total_mb': progress.get('total_mb', 0),
        'eta': progress.get('eta', ''),
        'filename': attributes.get('filename', ''),
        'method': attributes.get('method', 'unknown'),
        'error_message': attributes.get('error_message')
    }

def get_history():
    """Liest Aktivitäts-History"""
    history = read_api_json('history.json')
    return history if history else []

def get_status_text(live_status, service_running):
    """Generiert lesbaren Status-Text basierend auf Live-Status und Service-Status"""
    if not service_running:
        return 'Service gestoppt'
    
    status = live_status.get('status', 'idle')
    method = live_status.get('method', 'unknown')
    
    if status == 'idle':
        # Prüfe ob jemals ein Laufwerk erkannt wurde
        if not method or method == 'unknown':
            return 'Kein Laufwerk erkannt'
        else:
            return 'Wartet auf Medium'
    elif status == 'waiting':
        return 'Medium wird geprüft...'
    elif status == 'copying':
        return 'Kopiert Medium'
    elif status == 'completed':
        return 'Abgeschlossen'
    elif status == 'error':
        return 'Fehler aufgetreten'
    else:
        return 'Unbekannt'

# Routes
@app.route('/')
def index():
    """Haupt-Status-Seite"""
    config = get_config()
    version = get_version()
    service_running = get_service_status()
    disk_space = get_disk_space(config['output_dir'])
    iso_count = count_iso_files(config['output_dir'])
    live_status = get_live_status()
    status_text = get_status_text(live_status, service_running)
    
    return render_template('index.html',
        version=version,
        service_running=service_running,
        config=config,
        disk_space=disk_space,
        iso_count=iso_count,
        live_status=live_status,
        status_text=status_text,
        current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    )

@app.route('/config')
def config_page():
    """Konfigurations-Seite"""
    config = get_config()
    version = get_version()
    
    return render_template('config.html',
        version=version,
        config=config
    )

@app.route('/archive')
def archive_page():
    """Archiv-Übersicht-Seite"""
    version = get_version()
    
    return render_template('archive.html',
        version=version
    )

@app.route('/api/status')
def api_status():
    """API-Endpoint für Status-Abfrage (AJAX)"""
    config = get_config()
    live_status = get_live_status()
    
    return jsonify({
        'version': get_version(),
        'service_running': get_service_status(),
        'output_dir': config['output_dir'],
        'mqtt_enabled': config['mqtt_enabled'],
        'mqtt_broker': config['mqtt_broker'],
        'disk_space': get_disk_space(config['output_dir']),
        'iso_count': count_iso_files(config['output_dir']),
        'live_status': live_status,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/history')
def api_history():
    """API-Endpoint für Aktivitäts-History"""
    return jsonify(get_history())

@app.route('/api/archive')
def api_archive():
    """API-Endpoint für Archiv-Daten gruppiert nach Typ"""
    config = get_config()
    archives = get_iso_files_by_type(config['output_dir'])
    
    total = sum(len(files) for files in archives.values())
    
    return jsonify({
        'total': total,
        'by_type': archives,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/config', methods=['GET', 'POST'])
def api_config():
    """API-Endpoint für Konfigurations-Verwaltung"""
    if request.method == 'GET':
        # Konfiguration lesen
        return jsonify(get_config())
    
    elif request.method == 'POST':
        # Konfiguration speichern
        try:
            data = request.get_json()
            
            if not data:
                return jsonify({'success': False, 'message': 'Keine Daten empfangen'}), 400
            
            # Validierung
            required_fields = ['output_dir', 'mp3_quality', 'ddrescue_retries', 
                             'usb_detection_attempts', 'usb_detection_delay']
            for field in required_fields:
                if field not in data:
                    return jsonify({'success': False, 'message': f'Feld fehlt: {field}'}), 400
            
            # Lese aktuelle config.sh
            if not CONFIG_FILE.exists():
                return jsonify({'success': False, 'message': 'config.sh nicht gefunden'}), 404
            
            with open(CONFIG_FILE, 'r') as f:
                lines = f.readlines()
            
            # Aktualisiere Werte
            new_lines = []
            for line in lines:
                if line.strip().startswith('DEFAULT_OUTPUT_DIR='):
                    new_lines.append(f'DEFAULT_OUTPUT_DIR="{data["output_dir"]}"\n')
                elif line.strip().startswith('MP3_QUALITY='):
                    new_lines.append(f'MP3_QUALITY={data["mp3_quality"]}\n')
                elif line.strip().startswith('DDRESCUE_RETRIES='):
                    new_lines.append(f'DDRESCUE_RETRIES={data["ddrescue_retries"]}\n')
                elif line.strip().startswith('USB_DRIVE_DETECTION_ATTEMPTS='):
                    new_lines.append(f'USB_DRIVE_DETECTION_ATTEMPTS={data["usb_detection_attempts"]}\n')
                elif line.strip().startswith('USB_DRIVE_DETECTION_DELAY='):
                    new_lines.append(f'USB_DRIVE_DETECTION_DELAY={data["usb_detection_delay"]}\n')
                elif line.strip().startswith('MQTT_ENABLED='):
                    new_lines.append(f'MQTT_ENABLED={"true" if data.get("mqtt_enabled", False) else "false"}\n')
                elif line.strip().startswith('MQTT_BROKER='):
                    new_lines.append(f'MQTT_BROKER="{data.get("mqtt_broker", "")}"\n')
                elif line.strip().startswith('MQTT_PORT='):
                    new_lines.append(f'MQTT_PORT={data.get("mqtt_port", 1883)}\n')
                elif line.strip().startswith('MQTT_USER='):
                    new_lines.append(f'MQTT_USER="{data.get("mqtt_user", "")}"\n')
                elif line.strip().startswith('MQTT_PASSWORD='):
                    new_lines.append(f'MQTT_PASSWORD="{data.get("mqtt_password", "")}"\n')
                else:
                    new_lines.append(line)
            
            # Schreibe aktualisierte config.sh
            with open(CONFIG_FILE, 'w') as f:
                f.writelines(new_lines)
            
            return jsonify({
                'success': True, 
                'message': 'Konfiguration gespeichert. Service wird neu gestartet...'
            })
            
        except Exception as e:
            return jsonify({'success': False, 'message': f'Fehler beim Speichern: {str(e)}'}), 500

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
