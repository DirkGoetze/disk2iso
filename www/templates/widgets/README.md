# Widget Templates

Dieser Ordner enthält modulare Widget-Templates für optionale Module.

## Struktur

Widgets sind wiederverwendbare UI-Komponenten die dynamisch geladen werden:
- Werden via JavaScript injiziert (z.B. mqtt.js)
- Nutzen vorhandene CSS-Klassen aus main.css
- Werden vom Backend via `/api/{module}/widget` gerendert

## Vorhandene Widgets

- **mqtt_widget.html** - MQTT Service Status Widget (3-spaltig)
  - Geladen von: mqtt.js
  - Endpoint: /api/mqtt/widget
  - Injiziert in: .three-column-grid (index.html)

## Best Practices

1. **Naming Convention**: `{module}_widget.html`
2. **CSS**: Nutze vorhandene Klassen (card, info-row, badge, etc.)
3. **IDs**: Präfix mit Modulname (z.B. `mqtt-status`, `mqtt-indicator`)
4. **i18n**: Nutze `{{ t.TRANSLATION_KEY }}` für Texte
5. **Manifest**: Registriere in `conf/lib{module}.ini` unter `[modulefiles] html=`

## Beispiel: Neues Widget erstellen

```html
<!-- widgets/example_widget.html -->
<div class="card" id="example-widget">
    <h2>{{ t.EXAMPLE_TITLE }}</h2>
    <div class="info-row">
        <span class="info-label">{{ t.EXAMPLE_LABEL }}</span>
        <span class="info-value" id="example-value">-</span>
    </div>
</div>
```

```javascript
// static/js/example.js
async function loadExampleWidget() {
    const response = await fetch('/api/example/widget');
    const html = await response.text();
    document.querySelector('.target-container').innerHTML = html;
}
```

```python
# app.py
@app.route('/api/example/widget')
def api_example_widget():
    return render_template('widgets/example_widget.html', t=g.t)
```

```ini
# conf/libexample.ini
[modulefiles]
js=example.js
html=widgets/example_widget.html
```
