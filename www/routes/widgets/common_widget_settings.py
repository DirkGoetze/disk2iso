"""
disk2iso - Common Widget Settings Routes
Stellt die Kopier-Einstellungen bereit (Audio CD Encoding, ddrescue)
"""

import os
import sys
from flask import Blueprint, render_template, jsonify
from i18n import t

# Blueprint für Common Settings Widget
common_settings_bp = Blueprint('common_settings', __name__)

def get_common_settings():
    """
    Liest die Common-Einstellungen aus der Konfigurationsdatei
    Analog zu get_mqtt_config() in routes_mqtt.py
    """
    try:
        # Lese Einstellungen aus config.sh
        config_sh = '/opt/disk2iso/conf/config.sh'
        
        config = {
            "mp3_quality": 2,  # Default: Hohe Qualität
            "ddrescue_retries": 1,  # Default: 1 Wiederholung
        }
        
        if os.path.exists(config_sh):
            with open(config_sh, 'r') as f:
                for line in f:
                    line = line.strip()
                    
                    # MP3_QUALITY
                    if line.startswith('MP3_QUALITY='):
                        value = line.split('=', 1)[1].strip('"').strip("'")
                        try:
                            config['mp3_quality'] = int(value)
                        except ValueError:
                            pass
                    
                    # DDRESCUE_RETRIES
                    elif line.startswith('DDRESCUE_RETRIES='):
                        value = line.split('=', 1)[1].strip('"').strip("'")
                        try:
                            config['ddrescue_retries'] = int(value)
                        except ValueError:
                            pass
        
        return config
        
    except Exception as e:
        print(f"Fehler beim Lesen der Common-Einstellungen: {e}", file=sys.stderr)
        return {
            "mp3_quality": 2,
            "ddrescue_retries": 1,
        }


@common_settings_bp.route('/api/widgets/common/settings')
def api_common_settings_widget():
    """
    Rendert das Common Settings Widget
    Zeigt Kopier-Einstellungen (Audio CD, ddrescue)
    """
    config = get_common_settings()
    
    # Rendere Widget-Template
    return render_template('widgets/common_widget_settings.html',
                         config=config,
                         t=t)
