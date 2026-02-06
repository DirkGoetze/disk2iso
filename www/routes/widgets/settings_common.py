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
    Liest Common-Einstellungen via libsettings.sh (BASH)
    Python = Middleware ONLY - keine direkten File-Zugriffe!
    """
    try:
        import subprocess
        
        script = """
        source /opt/disk2iso/lib/libsettings.sh
        settings_get_value_conf "disk2iso" "DDRESCUE_RETRIES" "1"
        """
        
        result = subprocess.run(
            ['/bin/bash', '-c', script],
            capture_output=True,
            text=True,
            timeout=2
        )
        
        ddrescue_retries = 1
        if result.returncode == 0 and result.stdout.strip():
            try:
                ddrescue_retries = int(result.stdout.strip())
            except ValueError:
                pass
        
        return {
            "ddrescue_retries": ddrescue_retries,
        }
        
    except Exception as e:
        print(f"Fehler beim Lesen der Common-Einstellungen: {e}", file=sys.stderr)
        return {
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
    return render_template('widgets/settings_4x1_common.html',
                         settings=config,
                         t=t)

