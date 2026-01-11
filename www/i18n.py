#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
disk2iso i18n Module - Bash Language File Parser
Version 1.3.0 - 11.01.2026

Lädt Sprachdateien aus dem Bash-Format (readonly MSG_XYZ="...")
und stellt sie als Python-Dictionary für Flask/Jinja2-Templates bereit.
"""

import re
import os
from functools import lru_cache
from typing import Dict, Optional


def read_config_language() -> str:
    """
    Liest die LANGUAGE-Einstellung aus config.sh.
    
    Returns:
        str: Sprachcode (de, en, es, fr), Fallback: 'de'
    """
    # Pfad zur config.sh relativ zu diesem Modul
    config_path = os.path.join(
        os.path.dirname(os.path.dirname(__file__)),  # Gehe von www/ zu disk2iso/
        'lib',
        'config.sh'
    )
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Unterstütze sowohl "LANGUAGE=" als auch "readonly LANGUAGE="
                if 'LANGUAGE=' in line and not line.startswith('#'):
                    # Entferne LANGUAGE=, Quotes und Whitespace
                    lang = line.split('=', 1)[1].strip().strip('"\'')
                    # Validiere Sprachcode
                    if lang in ['de', 'en', 'es', 'fr']:
                        return lang
    except FileNotFoundError:
        print(f"Warning: {config_path} not found, using default language 'de'")
    except Exception as e:
        print(f"Error reading config.sh: {e}, using default language 'de'")
    
    return 'de'  # Fallback


@lru_cache(maxsize=16)
def _load_lang_file(filepath: str) -> Dict[str, str]:
    """
    Lädt eine einzelne Bash-Sprachdatei und parst MSG_* Konstanten.
    
    Args:
        filepath: Absoluter Pfad zur Sprachdatei
    
    Returns:
        Dict mit MSG_KEY -> "Wert" Mappings
    """
    translations = {}
    # Regex für: readonly MSG_XYZ="Beliebiger Text"
    # Unterstützt auch Sonderzeichen in den Werten
    pattern = re.compile(r'readonly\s+MSG_(\w+)="([^"]*)"')
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                match = pattern.match(line.strip())
                if match:
                    key = match.group(1)      # z.B. NAV_HOME
                    value = match.group(2)    # z.B. Startseite
                    translations[key] = value
    except FileNotFoundError:
        print(f"Warning: Language file {filepath} not found")
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
    
    return translations


@lru_cache(maxsize=4)
def load_web_translations(lang: str) -> Dict[str, str]:
    """
    Lädt alle Web-Interface Übersetzungen für die angegebene Sprache.
    
    Lädt lib-web.{lang} und optional auch Backend-Dateien zur Wiederverwendung.
    
    Args:
        lang: Sprachcode (de, en, es, fr)
    
    Returns:
        Dict mit allen MSG_* Konstanten
    """
    translations = {}
    
    # Basis-Pfad zum lang/-Ordner
    lang_dir = os.path.join(
        os.path.dirname(os.path.dirname(__file__)),  # Gehe von www/ zu disk2iso/
        'lang'
    )
    
    # 1. Lade Web-spezifische Texte (Priorität)
    web_file = os.path.join(lang_dir, f'lib-web.{lang}')
    translations.update(_load_lang_file(web_file))
    
    # 2. Optional: Lade Backend-Dateien zur Wiederverwendung
    # Diese haben niedrigere Priorität (werden NICHT überschrieben)
    backend_files = [
        f'lib-common.{lang}',      # MSG_ERROR, MSG_SUCCESS etc.
        f'lib-systeminfo.{lang}',  # MSG_VERSION, MSG_UPTIME etc.
    ]
    
    for filename in backend_files:
        filepath = os.path.join(lang_dir, filename)
        backend_trans = _load_lang_file(filepath)
        # Nur hinzufügen, wenn Key noch nicht existiert (Web hat Priorität)
        for key, value in backend_trans.items():
            if key not in translations:
                translations[key] = value
    
    return translations


def get_translations(lang: Optional[str] = None) -> Dict[str, str]:
    """
    Gibt Übersetzungen für die konfigurierte oder angegebene Sprache zurück.
    
    Args:
        lang: Optional Sprachcode, sonst aus config.sh
    
    Returns:
        Dict mit allen MSG_* Konstanten
    """
    if lang is None:
        lang = read_config_language()
    
    return load_web_translations(lang)


def clear_cache():
    """Leert den i18n-Cache (z.B. nach config.sh-Änderung)."""
    read_config_language.cache_clear()
    load_web_translations.cache_clear()
    _load_lang_file.cache_clear()
