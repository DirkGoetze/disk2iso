#!/usr/bin/env python3
"""
disk2iso Web Interface
Version: 1.2.0
Description: Flask-basierte Web-Oberfläche für disk2iso Monitoring
"""

from flask import Flask, render_template, jsonify, request, Response, g, send_file
import os
import sys
import json
import subprocess
from datetime import datetime
from pathlib import Path
from i18n import get_translations

app = Flask(__name__)

# Konfiguration
INSTALL_DIR = Path("/opt/disk2iso")
CONFIG_FILE = INSTALL_DIR / "conf" / "disk2iso.conf"
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
        "tmdb_api_key": "",
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
                        value = line.split('=', 1)[1]
                        # Entferne Anführungszeichen und Kommentare
                        if '#' in value:
                            value = value.split('#')[0]
                        value = value.strip().strip('"').strip()
                        config['mqtt_broker'] = value
                    elif line.startswith('MQTT_PORT='):
                        try:
                            config['mqtt_port'] = int(line.split('=', 1)[1].strip())
                        except:
                            pass
                    elif line.startswith('MQTT_USER='):
                        value = line.split('=', 1)[1]
                        if '#' in value:
                            value = value.split('#')[0]
                        value = value.strip().strip('"').strip()
                        config['mqtt_user'] = value
                    elif line.startswith('MQTT_PASSWORD='):
                        value = line.split('=', 1)[1]
                        if '#' in value:
                            value = value.split('#')[0]
                        value = value.strip().strip('"').strip()
                        config['mqtt_password'] = value
                    
                    # TMDB API Key
                    elif line.startswith('TMDB_API_KEY='):
                        value = line.split('=', 1)[1].strip()
                        if '#' in value:
                            value = value.split('#')[0]
                        value = value.strip().strip('"').strip()
                        config['tmdb_api_key'] = value
    except Exception as e:
        print(f"Fehler beim Lesen der Konfiguration: {e}", file=sys.stderr)
    
    return config

@app.before_request
def before_request():
    """Lädt Übersetzungen vor jedem Request"""
    g.t = get_translations()

@app.context_processor
def inject_translations():
    """Macht Übersetzungen in allen Templates verfügbar"""
    return {'t': g.get('t', {})}

def get_service_status_detailed(service_name):
    """Prüft detaillierten Status eines systemd Service
    
    Args:
        service_name: Name des Service ohne .service Endung
        
    Returns:
        dict mit 'status' (not_installed|inactive|active|error) und 'running' (bool)
    """
    try:
        # Prüfe ob Service existiert
        result_exists = subprocess.run(
            ['/usr/bin/systemctl', 'list-unit-files', f'{service_name}.service'],
            capture_output=True,
            text=True,
            timeout=2
        )
        
        if service_name not in result_exists.stdout:
            return {'status': 'not_installed', 'running': False}
        
        # Prüfe Service-Status
        result = subprocess.run(
            ['/usr/bin/systemctl', 'is-active', service_name],
            capture_output=True,
            text=True,
            timeout=2
        )
        
        status_text = result.stdout.strip()
        
        if status_text == 'active':
            return {'status': 'active', 'running': True}
        elif status_text == 'inactive':
            return {'status': 'inactive', 'running': False}
        elif status_text == 'failed':
            return {'status': 'error', 'running': False}
        else:
            return {'status': 'inactive', 'running': False}
            
    except:
        return {'status': 'error', 'running': False}

def get_service_status():
    """Prüft Status des disk2iso Service (Legacy-Kompatibilität)"""
    status = get_service_status_detailed('disk2iso')
    return status['running']

def get_disk_space(path):
    """Ermittelt freien Speicherplatz"""
    try:
        stat = os.statvfs(path)
        free_gb = (stat.f_bavail * stat.f_frsize) / (1024**3)
        total_gb = (stat.f_blocks * stat.f_frsize) / (1024**3)
        used_percent = ((total_gb - free_gb) / total_gb * 100) if total_gb > 0 else 0
        free_percent = (free_gb / total_gb * 100) if total_gb > 0 else 0
        return {
            'free_gb': round(free_gb, 2),
            'total_gb': round(total_gb, 2),
            'used_percent': round(used_percent, 1),
            'free_percent': round(free_percent, 1)
        }
    except:
        return {'free_gb': 0, 'total_gb': 0, 'used_percent': 0, 'free_percent': 0}

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
                    
                    # Prüfe ob .nfo Metadaten existieren
                    nfo_path = filepath.replace('.iso', '.nfo')
                    if os.path.exists(nfo_path):
                        try:
                            with open(nfo_path, 'r', encoding='utf-8') as nfo:
                                nfo_data = {}
                                for line in nfo:
                                    if '=' in line:
                                        key, value = line.strip().split('=', 1)
                                        nfo_data[key.lower()] = value
                                file_info['metadata'] = nfo_data
                        except:
                            pass
                    
                    # Prüfe ob Thumbnail existiert
                    thumb_path = filepath.replace('.iso', '-thumb.jpg')
                    if os.path.exists(thumb_path):
                        file_info['thumbnail'] = os.path.basename(thumb_path)
                    
                    # Determine type based on directory structure (primary) or filename pattern (fallback)
                    # Normalisiere Pfad-Komponenten
                    path_parts = os.path.normpath(root).split(os.sep)
                    filename_lower = filename.lower()
                    
                    # Prüfe zuerst Ordnerstruktur
                    if 'audio' in path_parts:
                        result['audio'].append(file_info)
                    elif 'dvd' in path_parts:
                        result['dvd'].append(file_info)
                    elif 'bluray' in path_parts or 'blu-ray' in path_parts or 'bd' in path_parts:
                        result['bluray'].append(file_info)
                    elif 'data' in path_parts:
                        result['data'].append(file_info)
                    # Fallback: Dateiname-Pattern
                    elif '_audio-cd_' in filename_lower or '_audiocd_' in filename_lower:
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
    
    # Für Audio-CDs: total_tracks aus attributes verwenden
    disc_type = attributes.get('disc_type', '')
    if disc_type == 'audio-cd':
        total_value = attributes.get('total_tracks', progress.get('total_mb', 0))
    else:
        total_value = progress.get('total_mb', 0)
    
    return {
        'status': status.get('status', 'idle'),
        'timestamp': status.get('timestamp', ''),
        'disc_label': attributes.get('disc_label', ''),
        'disc_type': disc_type,
        'disc_size_mb': attributes.get('disc_size_mb', 0),
        'progress_percent': progress.get('percent', 0),
        'progress_mb': progress.get('copied_mb', 0),
        'total_mb': total_value,
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
    t = g.get('t', {})
    
    if not service_running:
        return t.get('STATUS_SERVICE_STOPPED', 'Service stopped')
    
    status = live_status.get('status', 'idle')
    method = live_status.get('method', 'unknown')
    
    # Prüfe ob MusicBrainz User-Input benötigt
    mb_selection = read_api_json('musicbrainz_selection.json')
    if mb_selection and mb_selection.get('status') == 'waiting_user_input':
        return t.get('MUSICBRAINZ_WAITING', 'Waiting for user selection...')
    
    if status == 'idle':
        # Prüfe ob jemals ein Laufwerk erkannt wurde
        if not method or method == 'unknown':
            return t.get('STATUS_NO_DRIVE', 'No drive detected')
        else:
            return t.get('STATUS_WAITING_MEDIA', 'Waiting for media...')
    elif status == 'waiting':
        return t.get('STATUS_ANALYZING', 'Analyzing media...')
    elif status == 'copying':
        return t.get('STATUS_COPYING', 'Copying...')
    elif status == 'completed':
        return t.get('STATUS_COMPLETED', 'Completed')
    elif status == 'error':
        return t.get('STATUS_ERROR', 'Error occurred')
    else:
        return t.get('STATUS_UNKNOWN', 'Unknown')

# Routes
@app.route('/')
def index():
    """Haupt-Status-Seite"""
    config = get_config()
    version = get_version()
    service_running = get_service_status()
    
    # Service-Status für alle drei Services
    disk2iso_status = get_service_status_detailed('disk2iso')
    webui_status = {'status': 'active', 'running': True}  # Web-UI läuft wenn diese Route aufgerufen wird
    
    # MQTT-Status basierend auf config.sh
    if config['mqtt_enabled']:
        mqtt_status = {'status': 'active', 'running': True}
    else:
        mqtt_status = {'status': 'inactive', 'running': False}
    
    disk_space = get_disk_space(config['output_dir'])
    iso_count = count_iso_files(config['output_dir'])
    live_status = get_live_status()
    status_text = get_status_text(live_status, service_running)
    
    # Archive nach Typen
    archives = get_iso_files_by_type(config['output_dir'])
    archive_counts = {
        'data': len(archives['data']),
        'audio': len(archives['audio']),
        'dvd': len(archives['dvd']),
        'bluray': len(archives['bluray'])
    }
    
    return render_template('index.html',
        version=version,
        service_running=service_running,
        disk2iso_status=disk2iso_status,
        webui_status=webui_status,
        mqtt_status=mqtt_status,
        config=config,
        disk_space=disk_space,
        iso_count=iso_count,
        archive_counts=archive_counts,
        live_status=live_status,
        status_text=status_text,
        current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        active_page='index',
        page_title='INDEX_TITLE'
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
        version=version,
        active_page='archive',
        page_title='ARCHIVE_TITLE'
    )

@app.route('/logs')
def logs_page():
    """Log-Viewer-Seite"""
    version = get_version()
    
    return render_template('logs.html',
        version=version,
        active_page='logs',
        page_title='LOGS_TITLE'
    )

@app.route('/system')
def system_page():
    """System-Übersicht-Seite"""
    version = get_version()
    
    return render_template('system.html',
        version=version,
        active_page='system',
        page_title='SYSTEM_TITLE'
    )

@app.route('/help')
def help_page():
    """Hilfe-Seite mit Markdown-Dokumentation"""
    version = get_version()
    
    return render_template('help.html',
        version=version,
        active_page='help',
        page_title='HELP_TITLE'
    )

@app.route('/api/status')
def api_status():
    """API-Endpoint für Status-Abfrage (AJAX)"""
    config = get_config()
    live_status = get_live_status()
    
    # Archive-Counts ermitteln
    all_files = get_iso_files_by_type(config['output_dir'])
    archive_counts = {
        'data': len(all_files.get('data', [])),
        'audio': len(all_files.get('audio', [])),
        'dvd': len(all_files.get('dvd', [])),
        'bluray': len(all_files.get('bluray', []))
    }
    
    return jsonify({
        'version': get_version(),
        'service_running': get_service_status(),
        'output_dir': config['output_dir'],
        'mqtt_enabled': config['mqtt_enabled'],
        'mqtt_broker': config['mqtt_broker'],
        'disk_space': get_disk_space(config['output_dir']),
        'iso_count': count_iso_files(config['output_dir']),
        'archive_counts': archive_counts,
        'live_status': live_status,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/history')
def api_history():
    """API-Endpoint für Aktivitäts-History"""
    return jsonify(get_history())

@app.route('/api/musicbrainz/releases')
def api_musicbrainz_releases():
    """API-Endpoint für MusicBrainz Release-Auswahl"""
    releases = read_api_json('musicbrainz_releases.json')
    selection = read_api_json('musicbrainz_selection.json')
    
    if not releases:
        return jsonify({'status': 'no_data', 'releases': []}), 404
    
    return jsonify({
        'status': selection.get('status', 'unknown') if selection else 'unknown',
        'releases': releases.get('releases', []),
        'disc_id': releases.get('disc_id', ''),
        'track_count': releases.get('track_count', 0),
        'selected_index': selection.get('selected_index', 0) if selection else 0,
        'confidence': selection.get('confidence', 'unknown') if selection else 'unknown',
        'message': selection.get('message', '') if selection else ''
    })

@app.route('/api/musicbrainz/cover/<release_id>')
def api_musicbrainz_cover(release_id):
    """API-Endpoint zum Abrufen von Cover-Art (via Bash)"""
    try:
        # Temp-Verzeichnis
        temp_dir = INSTALL_DIR / '.temp'
        
        # Rufe Bash-Funktion auf
        script = f"""
        source {INSTALL_DIR}/lib/lib-cd-metadata.sh
        get_musicbrainz_cover "{release_id}" "{temp_dir}"
        """
        
        result = subprocess.run(
            ['/bin/bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=15
        )
        
        if result.returncode != 0:
            return jsonify({'error': g.t.get('API_ERROR_COVER_DOWNLOAD', 'Cover download failed')}), 500
        
        # Parse JSON-Output
        try:
            response_data = json.loads(result.stdout)
            
            if response_data.get('success'):
                cover_path = response_data.get('path')
                if cover_path and os.path.exists(cover_path):
                    return send_file(cover_path, mimetype='image/jpeg')
                else:
                    return jsonify({'error': g.t.get('API_ERROR_COVER_NOT_FOUND', 'Cover file not found')}), 404
            else:
                return jsonify({'error': response_data.get('message', g.t.get('API_ERROR_UNKNOWN', 'Unknown error'))}), 404
                
        except json.JSONDecodeError as e:
            return jsonify({'error': f'Ungültige JSON-Antwort: {str(e)}'}), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({'error': g.t.get('API_ERROR_TIMEOUT', 'Timeout')}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/musicbrainz/select', methods=['POST'])
def api_musicbrainz_select():
    """API-Endpoint zum Auswählen eines MusicBrainz Release"""
    try:
        data = request.get_json()
        
        if not data or 'index' not in data:
            return jsonify({'success': False, 'message': g.t.get('API_ERROR_INDEX_MISSING', 'Index missing')}), 400
        
        selected_index = int(data['index'])
        
        # Aktualisiere Selection-Status
        selection_data = {
            'status': 'confirmed',
            'selected_index': selected_index,
            'confidence': 'user_confirmed',
            'message': g.t.get('API_SUCCESS_SELECTION', 'Selected by user'),
            'timestamp': datetime.now().isoformat()
        }
        
        # Schreibe in API-Datei
        api_file = Path(CONFIG_FILE).parent.parent / 'api' / 'musicbrainz_selection.json'
        with open(api_file, 'w') as f:
            json.dump(selection_data, f, indent=2)
        
        return jsonify({'success': True, 'selected_index': selected_index})
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/musicbrainz/manual', methods=['POST'])
def api_musicbrainz_manual():
    """API-Endpoint für manuelle Metadaten-Eingabe"""
    try:
        data = request.get_json()
        
        required = ['artist', 'album', 'year']
        if not all(field in data for field in required):
            return jsonify({'success': False, 'message': g.t.get('API_ERROR_FIELDS_MISSING', 'Missing fields')}), 400
        
        # Speichere manuelle Metadaten
        manual_data = {
            'status': 'manual',
            'artist': data['artist'],
            'album': data['album'],
            'year': data['year'],
            'timestamp': datetime.now().isoformat()
        }
        
        api_file = Path(CONFIG_FILE).parent.parent / 'api' / 'musicbrainz_manual.json'
        with open(api_file, 'w') as f:
            json.dump(manual_data, f, indent=2)
        
        return jsonify({'success': True})
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/tmdb/results')
def api_tmdb_results():
    """API-Endpoint für TMDB-Suchergebnisse"""
    results = read_api_json('tmdb_results.json')
    
    if not results:
        return jsonify({'status': 'no_data', 'results': []}), 404
    
    return jsonify({
        'status': 'pending',
        'results': results.get('results', []),
        'total_results': results.get('total_results', 0)
    })

@app.route('/api/tmdb/select', methods=['POST'])
def api_tmdb_select():
    """API-Endpoint zum Auswählen eines TMDB Films"""
    try:
        data = request.get_json()
        
        if not data or 'index' not in data:
            return jsonify({'success': False, 'message': g.t.get('API_ERROR_INDEX_MISSING', 'Index missing')}), 400
        
        selected_index = int(data['index'])
        
        # Aktualisiere Selection-Status
        selection_data = {
            'status': 'confirmed',
            'selected_index': selected_index,
            'timestamp': datetime.now().isoformat()
        }
        
        # Schreibe in API-Datei
        api_file = Path(CONFIG_FILE).parent.parent / 'api' / 'tmdb_selection.json'
        with open(api_file, 'w') as f:
            json.dump(selection_data, f, indent=2)
        
        return jsonify({'success': True, 'selected_index': selected_index})
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

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

@app.route('/api/archive/thumbnail/<path:filename>')
def api_archive_thumbnail(filename):
    """API-Endpoint zum Abrufen von ISO-Thumbnails"""
    try:
        config = get_config()
        output_dir = Path(config['output_dir'])
        
        # Suche Thumbnail in allen Unterverzeichnissen
        for root, dirs, files in os.walk(output_dir):
            if filename in files:
                thumb_path = os.path.join(root, filename)
                return send_file(thumb_path, mimetype='image/jpeg')
        
        return jsonify({'error': g.t.get('API_ERROR_THUMBNAIL_NOT_FOUND', 'Thumbnail not found')}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/config', methods=['GET', 'POST'])
def api_config():
    """API-Endpoint für Konfigurations-Verwaltung (via Bash)"""
    if request.method == 'GET':
        # Konfiguration lesen via Bash
        try:
            script = f"""
            source {INSTALL_DIR}/lib/lib-config.sh
            get_all_config_values
            """
            
            result = subprocess.run(
                ['/bin/bash', '-c', script],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode != 0:
                return jsonify({'success': False, 'message': g.t.get('API_ERROR_CONFIG_READ', 'Error reading configuration')}), 500
            
            # Parse JSON-Output
            try:
                config_data = json.loads(result.stdout)
                if config_data.get('success'):
                    # Entferne success-Key für Kompatibilität
                    config_data.pop('success', None)
                    return jsonify(config_data)
                else:
                    return jsonify({'error': config_data.get('message', 'Unknown error')}), 500
            except json.JSONDecodeError as e:
                return jsonify({'error': f"{g.t.get('API_ERROR_INVALID_JSON', 'Invalid JSON response')}: {str(e)}"}), 500
                
        except subprocess.TimeoutExpired:
            return jsonify({'error': g.t.get('API_ERROR_TIMEOUT', 'Timeout')}), 500
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    
    elif request.method == 'POST':
        # Konfiguration speichern via Bash (inkl. Service-Neustart)
        try:
            data = request.get_json()
            
            if not data:
                return jsonify({'success': False, 'message': g.t.get('API_ERROR_NO_DATA', 'No data received')}), 400
            
            # Validierung der Pflichtfelder
            required_fields = ['output_dir', 'mp3_quality', 'ddrescue_retries', 
                             'usb_detection_attempts', 'usb_detection_delay']
            for field in required_fields:
                if field not in data:
                    return jsonify({'success': False, 'message': f"{g.t.get('API_ERROR_FIELD_MISSING', 'Field missing')}: {field}"}), 400
            
            # Konvertiere Python-Objekt zu JSON-String für Bash
            # Spezialbehandlung für mqtt_enabled (boolean -> string)
            bash_data = data.copy()
            if 'mqtt_enabled' in bash_data:
                bash_data['mqtt_enabled'] = bash_data['mqtt_enabled']  # bleibt boolean für json.dumps
            
            json_string = json.dumps(bash_data)
            # Escape für Bash (einfache Quotes verwenden)
            json_escaped = json_string.replace("'", "'\\''")
            
            # Rufe Bash-Funktion save_config_and_restart auf
            # Diese Funktion macht:
            # 1. Validierung (Pfad existiert, beschreibbar)
            # 2. Config-Update (alle Werte)
            # 3. Service-Neustart
            script = f"""
            source {INSTALL_DIR}/lib/lib-config.sh
            save_config_and_restart '{json_escaped}'
            """
            
            result = subprocess.run(
                ['/bin/bash', '-c', script],
                capture_output=True,
                text=True,
                timeout=15  # Timeout erhöht wegen Service-Restart
            )
            
            if result.returncode != 0:
                return jsonify({
                    'success': False,
                    'message': g.t.get('API_ERROR_CONFIG_SAVE', 'Error saving configuration'),
                    'error': result.stderr
                }), 500
            
            # Parse JSON-Response von Bash
            try:
                response_data = json.loads(result.stdout)
                if response_data.get('success'):
                    return jsonify(response_data)
                else:
                    return jsonify(response_data), 400
            except json.JSONDecodeError as e:
                return jsonify({
                    'success': False,
                    'message': f"{g.t.get('API_ERROR_INVALID_JSON', 'Invalid JSON response')}: {str(e)}",
                    'stdout': result.stdout
                }), 500
            
        except subprocess.TimeoutExpired:
            return jsonify({'success': False, 'message': f"{g.t.get('API_ERROR_TIMEOUT', 'Timeout')}: Config-Write"}), 500
        except Exception as e:
            return jsonify({'success': False, 'message': f'Fehler beim Speichern: {str(e)}'}), 500

@app.route('/api/browse_directories', methods=['POST'])
def browse_directories():
    """
    Listet Verzeichnisse für Directory Browser auf
    POST body: { "path": "/mnt" }
    Returns: { "success": true, "directories": [...], "current_path": "/mnt" }
    """
    try:
        data = request.get_json()
        path = data.get('path', '/')
        
        # Sicherheit: Nur absolute Pfade
        if not path.startswith('/'):
            path = '/'
        
        # Path object erstellen
        dir_path = Path(path)
        
        # Prüfen ob Verzeichnis existiert
        if not dir_path.exists():
            return jsonify({
                'success': False, 
                'message': f'Verzeichnis nicht gefunden: {path}'
            }), 404
        
        if not dir_path.is_dir():
            return jsonify({
                'success': False, 
                'message': f'Kein Verzeichnis: {path}'
            }), 400
        
        # Verzeichnisse sammeln
        directories = []
        
        # Parent Directory (..)
        if path != '/':
            parent = str(dir_path.parent)
            directories.append({
                'name': '..',
                'path': parent,
                'is_parent': True,
                'writable': False
            })
        
        # Unterverzeichnisse
        try:
            for item in sorted(dir_path.iterdir()):
                if item.is_dir():
                    # Versteckte Ordner überspringen (optional)
                    if item.name.startswith('.'):
                        continue
                    
                    # Schreibrechte prüfen
                    writable = os.access(str(item), os.W_OK)
                    
                    directories.append({
                        'name': item.name,
                        'path': str(item),
                        'is_parent': False,
                        'writable': writable
                    })
        except PermissionError:
            return jsonify({
                'success': False,
                'message': f'Keine Berechtigung für: {path}'
            }), 403
        
        return jsonify({
            'success': True,
            'current_path': str(dir_path),
            'directories': directories,
            'writable': os.access(str(dir_path), os.W_OK)
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Fehler: {str(e)}'
        }), 500

@app.route('/api/logs/current')
def api_logs_current():
    """API-Endpoint für aktuelles Log"""
    try:
        config = get_config()
        output_dir = Path(config['output_dir'])
        log_dir = output_dir / '.log'
        
        # Finde die neueste Log-Datei
        log_files = []
        if log_dir.exists():
            log_files = sorted(log_dir.glob('*.log'), key=lambda p: p.stat().st_mtime, reverse=True)
        
        if not log_files:
            return jsonify({
                'success': True,
                'logs': 'Keine Log-Dateien gefunden.',
                'lines': 0
            })
        
        # Lese die neueste Log-Datei (letzte 500 Zeilen)
        latest_log = log_files[0]
        with open(latest_log, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
            # Zeige die letzten 500 Zeilen
            recent_lines = lines[-500:] if len(lines) > 500 else lines
            log_content = ''.join(recent_lines)
        
        return jsonify({
            'success': True,
            'logs': log_content,
            'lines': len(recent_lines),
            'filename': latest_log.name
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Fehler beim Lesen des Logs: {str(e)}',
            'logs': '',
            'lines': 0
        })

@app.route('/api/logs/system')
def api_logs_system():
    """API-Endpoint für System-Log (journalctl)"""
    try:
        # Lese die letzten 200 Zeilen aus journalctl für disk2iso Service
        result = subprocess.run(
            ['journalctl', '-u', 'disk2iso', '-n', '200', '--no-pager'],
            capture_output=True,
            text=True,
            timeout=5
        )
        
        if result.returncode == 0:
            return jsonify({
                'success': True,
                'logs': result.stdout,
                'lines': len(result.stdout.split('\n'))
            })
        else:
            return jsonify({
                'success': False,
                'message': 'journalctl nicht verfügbar oder Fehler',
                'logs': result.stderr or 'Keine Ausgabe',
                'lines': 0
            })
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'message': 'Timeout beim Laden des System-Logs',
            'logs': '',
            'lines': 0
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Fehler beim Lesen des System-Logs: {str(e)}',
            'logs': '',
            'lines': 0
        })

@app.route('/api/logs/archived')
def api_logs_archived():
    """API-Endpoint für Liste der archivierten Log-Dateien"""
    try:
        config = get_config()
        output_dir = Path(config['output_dir'])
        log_dir = output_dir / '.log'
        
        if not log_dir.exists():
            return jsonify({
                'success': True,
                'files': []
            })
        
        # Sammle alle Log-Dateien
        log_files = []
        for log_file in sorted(log_dir.glob('*.log'), key=lambda p: p.stat().st_mtime, reverse=True):
            stat = log_file.stat()
            log_files.append({
                'name': log_file.name,
                'size': stat.st_size,
                'modified': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
            })
        
        return jsonify({
            'success': True,
            'files': log_files
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Fehler beim Lesen der Log-Dateien: {str(e)}',
            'files': []
        })

@app.route('/api/logs/archived/<filename>')
def api_logs_archived_file(filename):
    """API-Endpoint für eine spezifische archivierte Log-Datei"""
    try:
        # Sicherheitscheck: Nur .log Dateien erlauben und keine Pfad-Traversierung
        if not filename.endswith('.log') or '/' in filename or '\\' in filename or '..' in filename:
            return jsonify({
                'success': False,
                'message': 'Ungültiger Dateiname',
                'logs': '',
                'lines': 0
            }), 400
        
        config = get_config()
        output_dir = Path(config['output_dir'])
        log_dir = output_dir / '.log'
        log_file = log_dir / filename
        
        if not log_file.exists() or not log_file.is_file():
            return jsonify({
                'success': False,
                'message': 'Log-Datei nicht gefunden',
                'logs': '',
                'lines': 0
            }), 404
        
        # Lese die Log-Datei (letzte 1000 Zeilen)
        with open(log_file, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
            # Zeige die letzten 1000 Zeilen
            recent_lines = lines[-1000:] if len(lines) > 1000 else lines
            log_content = ''.join(recent_lines)
        
        return jsonify({
            'success': True,
            'logs': log_content,
            'lines': len(recent_lines),
            'filename': filename
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Fehler beim Lesen der Log-Datei: {str(e)}',
            'logs': '',
            'lines': 0
        })

def get_command_version(command, args=None):
    """Holt Version eines Kommandozeilen-Tools"""
    try:
        cmd = [command]
        if args:
            cmd.extend(args if isinstance(args, list) else [args])
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=3
        )
        
        output = result.stdout + result.stderr
        # Extrahiere Version aus Ausgabe
        import re
        version_match = re.search(r'(\d+\.[\d.]+)', output)
        if version_match:
            return version_match.group(1)
        return 'Installiert'
    except:
        return None

def get_package_version(package_name):
    """Holt installierte Version eines Debian-Pakets"""
    try:
        result = subprocess.run(
            ['dpkg', '-s', package_name],
            capture_output=True,
            text=True,
            timeout=2
        )
        
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if line.startswith('Version:'):
                    version = line.split(':', 1)[1].strip()
                    # Kürze Debian-Versionsnummern
                    if '-' in version:
                        version = version.split('-')[0]
                    if '+' in version:
                        version = version.split('+')[0]
                    return version
        return None
    except:
        return None

def get_available_package_version(package_name):
    """Holt verfügbare Version eines Pakets aus den Repositories"""
    try:
        result = subprocess.run(
            ['apt-cache', 'policy', package_name],
            capture_output=True,
            text=True,
            timeout=3
        )
        
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'Candidate:' in line:
                    version = line.split(':', 1)[1].strip()
                    if version and version != '(none)':
                        # Kürze Debian-Versionsnummern
                        if '-' in version:
                            version = version.split('-')[0]
                        if '+' in version:
                            version = version.split('+')[0]
                        return version
        return 'Unbekannt'
    except:
        return 'Unbekannt'

def check_software_versions():
    """Sammelt alle Software-Versionen"""
    software_list = []
    
    # Audio-CD Tools
    software_list.extend([
        {
            'name': 'cdparanoia',
            'display_name': 'cdparanoia',
            'package': 'cdparanoia',
            'version_cmd': ['cdparanoia', '--version']
        },
        {
            'name': 'abcde',
            'display_name': 'abcde',
            'package': 'abcde',
            'version_cmd': ['abcde', '-v']
        },
        {
            'name': 'lame',
            'display_name': 'LAME MP3 Encoder',
            'package': 'lame',
            'version_cmd': ['lame', '--version']
        },
        {
            'name': 'flac',
            'display_name': 'FLAC',
            'package': 'flac',
            'version_cmd': ['flac', '--version']
        },
        {
            'name': 'vorbis-tools',
            'display_name': 'Vorbis Tools',
            'package': 'vorbis-tools',
            'version_cmd': None  # Package version only
        }
    ])
    
    # DVD/Blu-ray Tools
    software_list.extend([
        {
            'name': 'makemkv',
            'display_name': 'MakeMKV',
            'package': 'makemkv-bin',
            'version_cmd': ['makemkvcon', '--version']
        },
        {
            'name': 'dvdbackup',
            'display_name': 'dvdbackup',
            'package': 'dvdbackup',
            'version_cmd': None
        },
        {
            'name': 'libbluray',
            'display_name': 'libbluray',
            'package': 'libbluray2',
            'version_cmd': None
        }
    ])
    
    # System Tools
    software_list.extend([
        {
            'name': 'ddrescue',
            'display_name': 'GNU ddrescue',
            'package': 'gddrescue',
            'version_cmd': ['ddrescue', '--version']
        },
        {
            'name': 'wodim',
            'display_name': 'wodim',
            'package': 'wodim',
            'version_cmd': ['wodim', '--version']
        },
        {
            'name': 'genisoimage',
            'display_name': 'genisoimage',
            'package': 'genisoimage',
            'version_cmd': ['genisoimage', '--version']
        },
        {
            'name': 'isoinfo',
            'display_name': 'isoinfo',
            'package': 'genisoimage',
            'version_cmd': ['isoinfo', '--version']
        }
    ])
    
    # Sammle Versionen
    results = []
    for soft in software_list:
        installed_version = None
        available_version = 'Unbekannt'
        
        # Versuche Paket-Version
        if soft['package']:
            installed_version = get_package_version(soft['package'])
            available_version = get_available_package_version(soft['package'])
        
        # Falls kein Paket oder Kommando angegeben, versuche Command-Version
        if not installed_version and soft['version_cmd']:
            installed_version = get_command_version(soft['version_cmd'][0], 
                                                    soft['version_cmd'][1:] if len(soft['version_cmd']) > 1 else None)
        
        # Prüfe ob Update verfügbar
        update_available = False
        if installed_version and available_version and available_version != 'Unbekannt':
            try:
                # Einfacher String-Vergleich
                if installed_version != available_version:
                    update_available = True
            except:
                pass
        
        results.append({
            'name': soft['name'],
            'display_name': soft['display_name'],
            'installed_version': installed_version,
            'available_version': available_version,
            'update_available': update_available
        })
    
    return results

def get_os_info():
    """Sammelt Betriebssystem-Informationen"""
    info = {
        'distribution': 'Unbekannt',
        'version': 'Unbekannt',
        'kernel': 'Unbekannt',
        'architecture': 'Unbekannt',
        'hostname': 'Unbekannt',
        'uptime': 'Unbekannt'
    }
    
    try:
        # Distribution und Version
        if os.path.exists('/etc/os-release'):
            with open('/etc/os-release', 'r') as f:
                for line in f:
                    if line.startswith('NAME='):
                        info['distribution'] = line.split('=', 1)[1].strip().strip('"')
                    elif line.startswith('VERSION='):
                        info['version'] = line.split('=', 1)[1].strip().strip('"')
        
        # Kernel
        result = subprocess.run(['uname', '-r'], capture_output=True, text=True, timeout=1)
        if result.returncode == 0:
            info['kernel'] = result.stdout.strip()
        
        # Architektur
        result = subprocess.run(['uname', '-m'], capture_output=True, text=True, timeout=1)
        if result.returncode == 0:
            info['architecture'] = result.stdout.strip()
        
        # Hostname
        result = subprocess.run(['hostname'], capture_output=True, text=True, timeout=1)
        if result.returncode == 0:
            info['hostname'] = result.stdout.strip()
        
        # Uptime
        result = subprocess.run(['uptime', '-p'], capture_output=True, text=True, timeout=1)
        if result.returncode == 0:
            info['uptime'] = result.stdout.strip().replace('up ', '')
    
    except Exception as e:
        print(f"Fehler beim Sammeln der OS-Infos: {e}", file=sys.stderr)
    
    return info

def get_disk2iso_info():
    """Sammelt disk2iso-spezifische Informationen"""
    info = {
        'version': get_version(),
        'service_status': 'unknown',
        'install_path': str(INSTALL_DIR),
        'python_version': 'Unbekannt'
    }
    
    try:
        # Service Status
        if get_service_status():
            info['service_status'] = 'active'
        else:
            result = subprocess.run(
                ['systemctl', 'is-active', 'disk2iso'],
                capture_output=True,
                text=True,
                timeout=2
            )
            info['service_status'] = result.stdout.strip()
        
        # Python Version
        result = subprocess.run(
            [sys.executable, '--version'],
            capture_output=True,
            text=True,
            timeout=1
        )
        if result.returncode == 0:
            info['python_version'] = result.stdout.strip().replace('Python ', '')
    
    except Exception as e:
        print(f"Fehler beim Sammeln der disk2iso-Infos: {e}", file=sys.stderr)
    
    return info

def get_software_list_from_system_json(software_data):
    """Konvertiert Software-Dict aus system.json zu Liste für Frontend"""
    software_list = []
    
    # Mapping von internen Namen zu Display-Namen
    software_mapping = {
        'cdparanoia': {'name': 'cdparanoia', 'display_name': 'cdparanoia'},
        'lame': {'name': 'lame', 'display_name': 'LAME MP3 Encoder'},
        'dvdbackup': {'name': 'dvdbackup', 'display_name': 'dvdbackup'},
        'ddrescue': {'name': 'ddrescue', 'display_name': 'GNU ddrescue'},
        'genisoimage': {'name': 'genisoimage', 'display_name': 'genisoimage'},
        'python': {'name': 'python', 'display_name': 'Python'},
        'flask': {'name': 'flask', 'display_name': 'Flask'},
        'mosquitto': {'name': 'mosquitto', 'display_name': 'Mosquitto'}
    }
    
    for key, mapping in software_mapping.items():
        version = software_data.get(key, 'Not installed')
        installed = version != 'Not installed'
        
        software_list.append({
            'name': mapping['name'],
            'display_name': mapping['display_name'],
            'installed_version': version if installed else None,
            'available_version': 'Unbekannt',
            'update_available': False
        })
    
    return software_list

@app.route('/api/system')
def api_system():
    """API-Endpoint für System-Informationen"""
    try:
        # Versuche zuerst system.json zu lesen (von disk2iso Service generiert)
        system_data = read_api_json('system.json')
        
        if system_data:
            # Nutze cached Daten und ergänze sie
            return jsonify({
                'success': True,
                'os': system_data.get('os', {}),
                'disk2iso': {
                    'version': get_version(),
                    'service_status': 'active' if get_service_status() else 'inactive',
                    'install_path': str(INSTALL_DIR),
                    'python_version': sys.version.split()[0],
                    'container': system_data.get('container', {})
                },
                'hardware': system_data.get('hardware', {}),
                'storage': system_data.get('storage', {}),
                'software': get_software_list_from_system_json(system_data.get('software', {})),
                'timestamp': system_data.get('timestamp', datetime.now().isoformat())
            })
        else:
            # Fallback: Sammle Daten live (wenn system.json nicht existiert)
            return jsonify({
                'success': True,
                'os': get_os_info(),
                'disk2iso': get_disk2iso_info(),
                'software': check_software_versions(),
                'timestamp': datetime.now().isoformat()
            })
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Fehler beim Sammeln der Systeminformationen: {str(e)}'
        }), 500

@app.route('/api/metadata/tmdb/search', methods=['POST'])
def api_tmdb_search():
    """API-Endpoint: Suche Film/TV-Serie in TMDB (nutzt Bash-Funktion)"""
    try:
        data = request.get_json()
        title = data.get('title', '').strip()
        media_type = data.get('type', 'movie')  # 'movie' oder 'tv'
        
        if not title:
            return jsonify({'success': False, 'message': 'Titel erforderlich'}), 400
        
        # Rufe Bash-Funktion auf (sicheres Argument-Array statt String-Interpolation)
        script = f"""
source {INSTALL_DIR}/lib/config.sh
source {INSTALL_DIR}/lib/lib-dvd-metadata.sh
search_tmdb_json "$1" "$2"
        """
        
        result = subprocess.run(
            ['/bin/bash', '-c', script, '--', title, media_type],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0 and result.stdout.strip():
            # Parse JSON-Output von Bash
            try:
                bash_response = json.loads(result.stdout)
                return jsonify(bash_response)
            except json.JSONDecodeError as e:
                print(f"[ERROR] JSON-Parse-Fehler: {e}, Output: {result.stdout}", file=sys.stderr)
                return jsonify({
                    'success': False,
                    'message': 'Ungültige Antwort vom Server'
                }), 500
        else:
            error_msg = result.stderr.strip() if result.stderr else 'TMDB-Suche fehlgeschlagen'
            print(f"[ERROR] Bash-Fehler: {error_msg}", file=sys.stderr)
            return jsonify({
                'success': False,
                'message': 'TMDB-Suche fehlgeschlagen'
            }), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'Timeout bei TMDB-Anfrage'}), 504
    except Exception as e:
        print(f"[ERROR] Unexpected: {str(e)}", file=sys.stderr)
        return jsonify({'success': False, 'message': f'Fehler: {str(e)}'}), 500

@app.route('/api/metadata/tmdb/apply', methods=['POST'])
def api_tmdb_apply():
    """API-Endpoint: Wende TMDB-Metadaten auf ISO an"""
    try:
        data = request.get_json()
        iso_path = data.get('iso_path', '')
        tmdb_id = data.get('tmdb_id', '')
        media_type = data.get('type', 'movie')
        title = data.get('title', '')
        rename_iso = data.get('rename_iso', False)
        
        if not iso_path or not os.path.exists(iso_path):
            return jsonify({'success': False, 'message': 'ISO-Datei nicht gefunden'}), 400
        
        if not tmdb_id:
            return jsonify({'success': False, 'message': 'TMDB-ID erforderlich'}), 400
        
        # Rufe Bash-Funktion auf
        script = f"""
source {INSTALL_DIR}/lib/config.sh
source {INSTALL_DIR}/lib/lib-common.sh
source {INSTALL_DIR}/lib/lib-logging.sh
source {INSTALL_DIR}/lib/lib-dvd-metadata.sh

add_metadata_to_existing_iso "{iso_path}" "{title}" "{media_type}" "{tmdb_id}"
result=$?

if [ $result -eq 0 ]; then
    echo "SUCCESS"
else
    echo "FAILED"
fi
        """
        
        result = subprocess.run(
            ['bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if "SUCCESS" in result.stdout:
            # Optional: ISO umbenennen
            new_path = iso_path
            if rename_iso and title:
                rename_script = f"""
source {INSTALL_DIR}/lib/config.sh
source {INSTALL_DIR}/lib/lib-common.sh
source {INSTALL_DIR}/lib/lib-logging.sh
source {INSTALL_DIR}/lib/lib-dvd-metadata.sh

new_path=$(rename_iso_with_metadata "{iso_path}" "{title}")
echo "$new_path"
                """
                rename_result = subprocess.run(
                    ['bash', '-c', rename_script],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                new_path = rename_result.stdout.strip()
            
            return jsonify({
                'success': True,
                'message': 'Metadaten erfolgreich hinzugefügt',
                'new_path': new_path
            })
        else:
            return jsonify({
                'success': False,
                'message': 'Fehler beim Hinzufügen der Metadaten',
                'error': result.stderr
            }), 500
            
    except Exception as e:
        return jsonify({'success': False, 'message': f'Fehler: {str(e)}'}), 500

@app.route('/api/metadata/musicbrainz/search', methods=['POST'])
def api_musicbrainz_search():
    """API-Endpoint: Suche Album in MusicBrainz (via Bash)"""
    try:
        data = request.get_json()
        artist = data.get('artist', '').strip()
        album = data.get('album', '').strip()
        iso_path = data.get('iso_path', '').strip()
        
        # Rufe Bash-Funktion auf
        script = """
        source /opt/disk2iso/lib/lib-cd-metadata.sh
        search_musicbrainz_json "$1" "$2" "$3"
        """
        
        result = subprocess.run(
            ['/bin/bash', '-c', script, '--', artist, album, iso_path],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode != 0:
            return jsonify({
                'success': False,
                'message': 'MusicBrainz-Suche fehlgeschlagen',
                'error': result.stderr
            }), 500
        
        # Parse JSON-Output
        try:
            response_data = json.loads(result.stdout)
            return jsonify(response_data)
        except json.JSONDecodeError as e:
            return jsonify({
                'success': False,
                'message': f'Ungültige JSON-Antwort: {str(e)}',
                'stdout': result.stdout
            }), 500
        
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'message': 'MusicBrainz-Suche: Zeitüberschreitung'}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': f'MusicBrainz-Suche fehlgeschlagen: {str(e)}'}), 500

@app.route('/api/metadata/musicbrainz/apply', methods=['POST'])
def api_musicbrainz_apply():
    """API-Endpoint: Wende MusicBrainz-Metadaten auf ISO an (Remaster)"""
    try:
        data = request.get_json()
        iso_path = data.get('iso_path', '')
        release_id = data.get('release_id', '')
        
        print(f"[DEBUG] Remaster-Request: iso_path={iso_path}, release_id={release_id}", file=sys.stderr)
        
        if not iso_path or not os.path.exists(iso_path):
            print(f"[ERROR] ISO nicht gefunden: {iso_path}", file=sys.stderr)
            return jsonify({'success': False, 'message': 'ISO-Datei nicht gefunden'}), 400
        
        if not release_id:
            print(f"[ERROR] Keine Release-ID", file=sys.stderr)
            return jsonify({'success': False, 'message': g.t.get('API_ERROR_RELEASE_ID_REQUIRED', 'MusicBrainz Release ID required')}), 400
        
        # Starte Remaster-Prozess im Hintergrund
        script = f"""
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

source {INSTALL_DIR}/lib/config.sh
source {INSTALL_DIR}/lib/lib-common.sh
source {INSTALL_DIR}/lib/lib-logging.sh
source {INSTALL_DIR}/lib/lib-cd-metadata.sh

remaster_audio_iso_with_metadata "{iso_path}" "{release_id}"
result=$?

if [ $result -eq 0 ]; then
    echo "SUCCESS"
else
    echo "FAILED"
fi
        """
        
        print(f"[DEBUG] Starte Remaster-Prozess...", file=sys.stderr)
        
        # Timeout erhöhen (Remaster kann 5-10 Minuten dauern)
        result = subprocess.run(
            ['/bin/bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=600  # 10 Minuten
        )
        
        print(f"[DEBUG] Remaster beendet. Exit-Code: {result.returncode}", file=sys.stderr)
        print(f"[DEBUG] STDOUT: {result.stdout[:500]}", file=sys.stderr)
        print(f"[DEBUG] STDERR: {result.stderr[:500]}", file=sys.stderr)
        
        if "SUCCESS" in result.stdout:
            return jsonify({
                'success': True,
                'message': g.t.get('API_SUCCESS_REMASTER', 'Audio ISO successfully recreated with correct tags')
            })
        else:
            error_msg = result.stderr if result.stderr else "Unbekannter Fehler"
            print(f"[ERROR] Remaster fehlgeschlagen: {error_msg}", file=sys.stderr)
            return jsonify({
                'success': False,
                'message': g.t.get('API_ERROR_REMASTER_FAILED', 'Error remastering audio ISO'),
                'error': error_msg
            }), 500
            
    except subprocess.TimeoutExpired:
        print(f"[ERROR] Remaster-Timeout", file=sys.stderr)
        return jsonify({
            'success': False,
            'message': g.t.get('API_ERROR_REMASTER_TIMEOUT', 'Timeout: Remaster process takes too long')
        }), 500
    except Exception as e:
        print(f"[ERROR] Exception in api_musicbrainz_apply: {str(e)}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return jsonify({'success': False, 'message': f'Fehler: {str(e)}'}), 500

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
