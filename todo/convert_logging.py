#!/usr/bin/env python3
"""
Konvertiert log_message Aufrufe zu kategorisierten Log-Funktionen
"""

import re
import sys
from pathlib import Path

# Kategorisierungs-Regeln (Reihenfolge ist wichtig!)
CATEGORIZATION_RULES = [
    # ERRORS (höchste Priorität)
    (r'(?i)(ERROR|FEHLER|MSG_ERROR|fehlgeschlagen|failed|nicht gefunden|not found|missing|kann nicht|cannot|insufficient)', 'log_error'),
    
    # WARNINGS
    (r'(?i)(WARNING|WARNUNG|MSG_WARNING|übersprungen|skipped|optional|limited|eingeschränkt)', 'log_warning'),
    
    # DEBUG
    (r'(?i)(DEBUG|MSG_DEBUG)', 'log_debug'),
    
    # DEFAULT: INFO
    (r'.*', 'log_info'),
]

def categorize_line(line):
    """Kategorisiert eine log_message Zeile"""
    for pattern, category in CATEGORIZATION_RULES:
        if re.search(pattern, line):
            return category
    return 'log_info'

def process_file(filepath):
    """Verarbeitet eine Datei und gibt Konvertierungs-Statistiken aus"""
    
    conversions = {
        'log_error': 0,
        'log_warning': 0,
        'log_debug': 0,
        'log_info': 0,
    }
    
    lines = []
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            lines = content.split('\n')
    except Exception as e:
        print(f"❌ Fehler beim Lesen von {filepath}: {e}")
        return
    
    changes = 0
    new_lines = []
    
    for i, line in enumerate(lines, 1):
        # Überspringe Kommentare
        stripped = line.lstrip()
        if stripped.startswith('#'):
            new_lines.append(line)
            continue
        
        # Überspringe Funktionsdefinition
        if 'log_message()' in line and '{' in line:
            new_lines.append(line)
            continue
        
        # Überspringe Logging-System interne Aufrufe
        if 'declare -f log_message' in line or 'if declare -f log_message' in line:
            new_lines.append(line)
            continue
        
        # Finde log_message Aufrufe
        if 'log_message' in line and not 'log_message()' in line:
            category = categorize_line(line)
            
            # Ersetze nur das log_message, nicht die Parameter
            new_line = line.replace('log_message', category, 1)
            
            if new_line != line:
                changes += 1
                conversions[category] += 1
                print(f"  Zeile {i:4d}: {category:12s} {stripped[:60]}...")
            
            new_lines.append(new_line)
        else:
            new_lines.append(line)
    
    if changes > 0:
        # Schreibe geänderte Datei
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write('\n'.join(new_lines))
            
            print(f"\n✅ {filepath.name}: {changes} Änderungen")
            for cat, count in sorted(conversions.items()):
                if count > 0:
                    print(f"   - {cat}: {count}")
        except Exception as e:
            print(f"❌ Fehler beim Schreiben von {filepath}: {e}")
    else:
        print(f"ℹ️  {filepath.name}: Keine Änderungen")

def main():
    base_dir = Path('/home/dirk/Projects/disk2iso')
    lib_dir = base_dir / 'lib'
    
    print("="*70)
    print("LOG-KATEGORISIERUNG: log_message → log_error/warning/debug/info")
    print("="*70)
    
    # Verarbeite alle .sh Dateien in lib/
    for sh_file in sorted(lib_dir.glob('*.sh')):
        print(f"\n📄 {sh_file.name}")
        print("-"*70)
        process_file(sh_file)
    
    print("\n" + "="*70)
    print("✅ FERTIG")
    print("="*70)

if __name__ == '__main__':
    main()
