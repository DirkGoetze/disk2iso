"""
disk2iso - Drivestat Widget Settings Routes
Stellt die Hardware-Erkennungs-Einstellungen bereit (USB Detection)
"""

import os
import sys
from flask import Blueprint, render_template, jsonify
from i18n import t

# Blueprint für Drivestat Settings Widget
drivestat_settings_bp = Blueprint('drivestat_settings', __name__)

def get_drivestat_settings():
    """
    Liest die Drivestat-Einstellungen aus der Konfigurationsdatei
    Analog zu get_mqtt_config() in routes_mqtt.py
    """
    try:
        # Lese Einstellungen aus config.sh
        config_sh = '/opt/disk2iso/conf/config.sh'
        
        config = {
            "usb_detection_attempts": 5,  # Default
            "usb_detection_delay": 10,  # Default
        }
        
        if os.path.exists(config_sh):
            with open(config_sh, 'r') as f:
                for line in f:
                    line = line.strip()
                    
                    # USB_DRIVE_DETECTION_ATTEMPTS
                    if line.startswith('USB_DRIVE_DETECTION_ATTEMPTS='):
                        value = line.split('=', 1)[1].strip('"').strip("'")
                        try:
                            config['usb_detection_attempts'] = int(value)
                        except ValueError:
                            pass
                    
                    # USB_DRIVE_DETECTION_DELAY
                    elif line.startswith('USB_DRIVE_DETECTION_DELAY='):
                        value = line.split('=', 1)[1].strip('"').strip("'")
                        try:
                            config['usb_detection_delay'] = int(value)
                        except ValueError:
                            pass
        
        return config
        
    except Exception as e:
        print(f"Fehler beim Lesen der Drivestat-Einstellungen: {e}", file=sys.stderr)
        return {
            "usb_detection_attempts": 5,
            "usb_detection_delay": 10,
        }


@drivestat_settings_bp.route('/api/widgets/drivestat/settings')
def api_drivestat_settings_widget():
    """
    Rendert das Drivestat Settings Widget
    Zeigt Hardware-Erkennungs-Einstellungen (USB Detection)
    """
    config = get_drivestat_settings()
    
    # Rendere Widget-Template
    return render_template('widgets/drivestat_widget_settings.html',
                         config=config,
                         t=t)
