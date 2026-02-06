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
    Liest Drivestat-Einstellungen via libsettings.sh (BASH)
    Python = Middleware ONLY - keine direkten File-Zugriffe!
    """
    try:
        import subprocess
        
        # USB Detection Attempts
        script_attempts = """
        source /opt/disk2iso/lib/libsettings.sh
        settings_get_value_conf "disk2iso" "USB_DRIVE_DETECTION_ATTEMPTS" "5"
        """
        
        result_attempts = subprocess.run(
            ['/bin/bash', '-c', script_attempts],
            capture_output=True,
            text=True,
            timeout=2
        )
        
        usb_detection_attempts = 5
        if result_attempts.returncode == 0 and result_attempts.stdout.strip():
            try:
                usb_detection_attempts = int(result_attempts.stdout.strip())
            except ValueError:
                pass
        
        # USB Detection Delay
        script_delay = """
        source /opt/disk2iso/lib/libsettings.sh
        settings_get_value_conf "disk2iso" "USB_DRIVE_DETECTION_DELAY" "10"
        """
        
        result_delay = subprocess.run(
            ['/bin/bash', '-c', script_delay],
            capture_output=True,
            text=True,
            timeout=2
        )
        
        usb_detection_delay = 10
        if result_delay.returncode == 0 and result_delay.stdout.strip():
            try:
                usb_detection_delay = int(result_delay.stdout.strip())
            except ValueError:
                pass
        
        return {
            "usb_detection_attempts": usb_detection_attempts,
            "usb_detection_delay": usb_detection_delay,
        }
        
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
    return render_template('widgets/settings_4x1_drivestat.html',
                         settings=config,
                         t=t)

