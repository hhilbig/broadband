**Verdichtete Zusammenfassung Ihrer offenen Sach- und Klärungsfragen (ohne Punkte 6–8, dafür mit zusätzlichen Details)**

1. **Verfügbarkeit historischer Gemeindedaten (E-Mail vom 28. Mai 2025)**
   * Ob es tabellarische Daten **vor** dem im Download-Bereich verfügbaren Datenstand 06/2022 gibt, um einen **lückenlosen Panel-Datensatz** auf Gemeindeebene zu konstruieren.
   * Konkreter Wunsch: vollständige Zeitreihe aller Gemeindecodes mit jährlichen (oder halbjährlichen) Versorgungskennzahlen, damit zeitliche Entwicklungen modelliert werden können.
2. **Paket 2 – Spalten- und Variableninterpretation (30. Mai 2025, 12:54)**
   * **HH_ges** und **GemFl**: Bestätigung erbeten, dass es sich um **absolute Strukturmerkmale** (Anzahl Haushalte bzw. Gemeindefläche in km²) handelt und **nicht** um Breitband-Verfügbarkeitswerte.
   * **Namensschema dsl_gtoe_16_mbits (bzw. *_gtoe_X_mbits)**
     * Bedeutet **gtoe** „greater than or equal“?
     * Bezieht sich die nachgestellte Zahl (z. B. 16) eindeutig auf die **Bandbreitenklasse in Mbit/s**?
     * Fehlende Technologiepräfixe in manchen Spaltennamen: Wie ist dann zu unterscheiden, ob sich die Kennzahl auf DSL, CATV, Funk o. Ä. bezieht?
   * Ziel: saubere Zuordnung jeder Spalte zu einer Technologie-Bandbreiten-Kategorie für automatisiertes Einlesen.
3. **Paket 3 – Dateinamen­logik und Datenauswahl (30. Mai 2025, 12:54)**
   * **Prä- und Suffixe**
     * ***stats***: Statistische Basisdaten (Karten-/Gemeindeflächen-Aggregationen?)
     * ***gewerbe_gwg***: Kennzahlen für **gewerb­liche Anschlüsse** bzw. Groß- und Einzelhandels­standorte?
     * ***privat***: Kennzahlen für **private Haushalte**.
     * **_ende**, **_mitte**: Stichtage (Jahresende vs. Jahresmitte).
     * **_1**, **_2**: Mehrere Berichtsvarianten oder Korrekturstände innerhalb desselben Stichtags.
   * **Eindeutige Filterregel**: Wie lässt sich programmgesteuert sicherstellen, dass nur **private-Haushaltsdateien** geladen werden? Reicht das Teilwort „privat“ oder sind weitere Prüfkriterien nötig?
   * **„Gemeindebezirke“-Dateien**: Klärung, ob es sich um intra­kommunale Untergliederungen (z. B. Ortsteile) handelt oder lediglich um alternative Geometrie­grenzen.
4. **Sprunghafte Anstiege 2014 → 2015 (30. Mai 2025, 22:03)**
   * Im Sheet **verf_gemeinde_10_18_percent** der Datei **verf_privat_alle_2010_2018.xls** zeigen sich für alle Bandbreitenklassen starke Sprünge:
     * ≥ 2 Mbit/s: Ø 39,6 % → 97,6 %
     * ≥ 16 Mbit/s: Ø 22,7 % → 66,6 %
     * ≥ 50 Mbit/s: Ø 14,1 % → 38,9 %
   * Erbeten wurde eine Einordnung, ob diese Zuwächse primär auf **methodische Umstellungen** (z. B. neue Meldestandards, geänderte Aggregations­ebene, andere Beteiligungsquote der Betreiber) oder auf einen **tatsächlichen Infrastrukturausbau** zurückzuführen sind.
   * Wichtig, um zeitliche Trends nicht irrtümlich als Policy-Effekte zu interpretieren.
5. **Paket 1 – Frühjahre 2005-2008: Spalte verf_dsl (31. Mai 2025, 13:05)**
   * In den Dateien **2005_DSL_Verfügbarkeit_Deutschland.xlsx** bis **2008_…** existiert nur **verf_dsl** ohne Band­breitenangabe.
   * Klärung, ob diese Spalte
     1. jede **DSL-Grundversorgung** unabhängig von der Downstream-Rate abbildet, oder
     2. eine implizite Mindestgeschwindigkeit (z. B. ≥ 1 Mbit/s oder ≥ 2 Mbit/s) besitzt.
   * Diese Information ist nötig, um die frühe DSL-Versorgung korrekt mit späteren, explizit klassifizierten Bandbreiten­stufen zu vergleichen und Zeitreihen­brüche zu vermeiden.

Damit deckt die Liste alle verbliebenen inhaltlichen Fragen ab, die für Ihre geplante Panel-Konzeption, Variablen­harmonisierung und Interpretation der Breitbanddaten zentral sind.
