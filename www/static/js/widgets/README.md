# Widget JavaScript

Dieser Ordner enthält JavaScript für modulare Widgets.

## Struktur

Widget-JS lädt und steuert die zugehörigen HTML-Widgets aus `templates/widgets/`:
- Dynamisches Laden via AJAX
- Widget-Injection in bestehende Container
- Echtzeit-Updates und Event-Handling

## Vorhandene Widgets

- **mqtt.js** - MQTT Service Widget Controller
  - Lädt: templates/widgets/mqtt_widget.html
  - Endpoint: /api/mqtt/widget
  - Exports: window.mqtt.init(), window.mqtt.updateStatus()

## Best Practices

1. **Naming Convention**: `{module}.js` (entspricht HTML-Widget)
2. **IIFE Pattern**: Nutze `(function() { ... })()` für Isolation
3. **Namespacing**: Exportiere via `window.{module} = { ... }`
4. **Auto-Init**: DOMContentLoaded Event für automatische Initialisierung
5. **Error Handling**: Graceful Degradation wenn Widget nicht geladen werden kann

## Beispiel: Neues Widget-JS

```javascript
// widgets/example.js
(function() {
    'use strict';
    
    async function loadExampleWidget() {
        const response = await fetch('/api/example/widget');
        const html = await response.text();
        document.querySelector('.target-container').innerHTML = html;
    }
    
    function updateExampleData(data) {
        const element = document.getElementById('example-value');
        if (element) element.textContent = data.value;
    }
    
    function initExample() {
        console.log('[Example] Modul initialisiert');
        loadExampleWidget();
    }
    
    // Export
    window.example = {
        init: initExample,
        update: updateExampleData
    };
    
    // Auto-Init
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initExample);
    } else {
        initExample();
    }
})();
```

## Integration mit module-loader.js

```javascript
// module-loader.js
MODULE_DEFINITIONS = {
    'example': {
        files: ['widgets/example.js'],
        init: function() {
            if (window.example) window.example.init();
        }
    }
}
```

## Ordner-Parallelität

```
templates/widgets/        ←→  static/js/widgets/
├── mqtt_widget.html     ←→  ├── mqtt.js
├── example_widget.html  ←→  ├── example.js
└── README.md                └── README.md
```
