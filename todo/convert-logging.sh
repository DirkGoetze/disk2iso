#!/bin/bash
# Automatische Konvertierung von log_message zu kategorisierten Log-Funktionen

# Kategorisierungs-Regeln (Regex-Patterns)
declare -A ERROR_PATTERNS=(
    ["ERROR"]="log_error"
    ["FEHLER"]="log_error"
    ["fehlgeschlagen"]="log_error"
    ["failed"]="log_error"
    ["nicht gefunden"]="log_error"
    ["not found"]="log_error"
    ["missing"]="log_error"
    ["kann nicht"]="log_error"
    ["cannot"]="log_error"
)

declare -A WARNING_PATTERNS=(
    ["WARNING"]="log_warning"
    ["WARNUNG"]="log_warning"
    ["übersprungen"]="log_warning"
    ["skipped"]="log_warning"
    ["optional"]="log_warning"
)

declare -A DEBUG_PATTERNS=(
    ["DEBUG"]="log_debug"
)

# Funktion: Kategorisiere eine log_message Zeile
categorize_log() {
    local line="$1"
    
    # Extrahiere die Message-Variable
    local msg_var=$(echo "$line" | grep -oP '\$MSG_\w+' | head -1)
    
    # ERROR prüfen
    for pattern in "${!ERROR_PATTERNS[@]}"; do
        if echo "$line" | grep -qi "$pattern"; then
            echo "${ERROR_PATTERNS[$pattern]}"
            return
        fi
    done
    
    # WARNING prüfen
    for pattern in "${!WARNING_PATTERNS[@]}"; do
        if echo "$line" | grep -qi "$pattern"; then
            echo "${WARNING_PATTERNS[$pattern]}"
            return
        fi
    done
    
    # DEBUG prüfen
    for pattern in "${!DEBUG_PATTERNS[@]}"; do
        if echo "$line" | grep -qi "$pattern"; then
            echo "${DEBUG_PATTERNS[$pattern]}"
            return
        fi
    done
    
    # Default: log_info
    echo "log_info"
}

# Hauptfunktion
convert_file() {
    local file="$1"
    
    echo "Analysiere: $file"
    
    # Finde alle log_message Zeilen
    grep -n "log_message" "$file" | while IFS=: read -r line_num line_content; do
        # Überspringe Kommentare
        if echo "$line_content" | grep -q "^\s*#"; then
            continue
        fi
        
        # Überspringe log_message Definition
        if echo "$line_content" | grep -q "^log_message()"; then
            continue
        fi
        
        # Kategorisiere
        new_func=$(categorize_log "$line_content")
        
        echo "  Zeile $line_num: log_message → $new_func"
        echo "    $line_content"
    done
}

# Durchlaufe alle .sh Dateien
for file in lib/*.sh; do
    if [[ -f "$file" ]]; then
        convert_file "$file"
        echo ""
    fi
done
