"""
disk2iso - Modulare Route Blueprints
Jedes optionale Modul kann eigene Routen registrieren
"""

from flask import Blueprint

# Core Config Blueprint (field-by-field API)
from .settings import config_bp

# MQTT Blueprint wird in routes_mqtt.py definiert
from .routes_mqtt import mqtt_bp

__all__ = ['config_bp', 'mqtt_bp']
