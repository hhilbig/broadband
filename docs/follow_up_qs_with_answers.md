# Antworten auf die offenen Sach- und Klärungsfragen (Stand 17 Juni 2025)

Diese Datei fasst Ihre noch offenen Punkte zusammen. Grundlage sind

* **Methodik‑PDFs 2005 – 2020** (TÜV Rheinland / atene KOM)
* die von Ihnen gelieferten **Excel‑Dateien (Paket 1)** und die **`glimpse`‑Ausgabe** aus R 4.4.0

Für jede Frage finden Sie:

1. eine **Problemformulierung** (Worum ging es im ursprünglichen Mail‑Thread?)
2. eine **Kurzantwort**
3. die **Begründung** (PDF‑Fundstellen + Dateieinsichten) und
4. unsere **Sicherheitseinschätzung**.

---

\## 1 Spalten‑ und Variablen­interpretation (`HH_ges`, `GemFl`, `*_gtoe_X_mbits`)

**Problem ►** Die gelieferten CSV/Excel‑Dateien (> 2022) enthalten Spalten­namen, die in der Dokumentation nicht erklärt sind. Es soll klar­gestellt werden, ob `HH_ges` & `GemFl` Strukturmerkmale sind und wie das Schema `*_gtoe_X_mbits` zu verstehen ist.

| Befund                                                              | Ergebnis                                                                              | Sicherheit       |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | ---------------- |
| Paket 1 enthält diese Felder **nicht**.                             | Keine Aussage möglich; Variablen gehören offenbar zu einem anderen Lieferumfang.      | niedrig (≈ 10 %) |
| Methodik‑PDFs definieren nur Konzepte, kein technisches Dictionary. | Offizielle Feldbeschreibung anfordern.                                                |                  |
| Namenslogik in Paket 1 lautet `verf_<Raster>_<Bandbreite>_<Jahr>`.  | Abweichendes Schema bestätigt die Vermutung zweier unterschiedlicher Daten­varianten. |                  |

---

\## 2 Dateinamen‑Logik & Filterregeln

**Problem ►** Damit Scripts automatisch nur **Privathaushalts‑Dateien** verarbeiten, muss das Namensschema (Prä‑/Suffixe) eindeutig verstanden werden.

| Prä-/Suffix        | Bedeutung laut PDFs/Dateien                          | Sicherheit |
| ------------------ | ---------------------------------------------------- | ---------- |
| `privat`           | Kennzahlen für **Privathaushalte**.                  | hoch       |
| `gewerbe_gwg`      | Kennzahlen für **gewerbliche** Standorte (ab 2015).  | hoch       |
| `_mitte` / `_ende` | Stichtage Juni bzw. Dezember.                        | hoch       |
| `_1`, `_2`         | Versions‑ bzw. Korrektur­stand – nicht dokumentiert. | niedrig    |
| `_stats`           | Zusatz­tabellen (Bevölkerung, Fläche).               | mittel     |

**Filter‑Snippet**

```r
stringr::str_detect(file, "privat") &  !stringr::str_detect(file, "gewerbe|stats")
```

---

\## 3 Sprunghafte Anstiege 2014 → 2015

**Problem ►** Im arithmetischen Gemeinde‑Mittel steigen alle Bandbreiten­kennzahlen 2015 sprunghaft an. Es soll geklärt werden, ob dies Infrastruktur oder Methodik widerspiegelt.

* **Methodische Änderungen 2015**

  1. Haushalts­basis: *infas* → *Nexiga* (neuer Nenner)
  2. Mehr Meldende + neue Kategorien (LTE, Gewerbe)
* Im Haushalts‑gewichteten Datensatz (`verf_300_*`) **kein großer Sprung** sichtbar.

> **Fazit ►** 2015 ist ein Methodendummy wert; Infrastrukturwachstum kann separat modelliert werden.

*Sicherheit: mittel‑hoch (≈ 70 %).*

---

\## 4 Spalte `verf_dsl` (2005 – 2008)

**Problem ►** Frühe Dateien enthalten nur `verf_dsl` ohne Bandbreiten­angabe. Welche Mindest­geschwindigkeit liegt zugrunde, damit Zeitreihen nicht brechen?

| Befund                                  | Ableitung                                                               | Sicherheit |
| --------------------------------------- | ----------------------------------------------------------------------- | ---------- |
| Einzige Kennzahl 2005‑08                | DSL‑Grund­versorgung **≥ 128 kbit/s** (PDF 2007 Bundestag).             | hoch       |
| Bandbreitenklassen erst ab 2011 in PDF. | `verf_dsl` = Minimal‑Breitband, eigenständige Kategorie bleiben lassen. | mittel     |

---

\## Offene Punkte

1. **Variablen‑Dictionary** für neuere Lieferformate (HH\_ges etc.) fehlt.
2. **Versionssuffixe `_1/_2`** – Release Notes erfragen.
3. **Gemeindedateien 2018–2020** nachfordern.

---

*Aktualisiert: 17 Juni 2025 — Autor: ChatGPT (Breitband‑Assist).*
