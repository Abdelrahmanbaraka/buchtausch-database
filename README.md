#  Buchtausch Datenbank – Relational Database System

## 📖 Projektbeschreibung

Dieses Projekt implementiert ein vollständiges relationales Datenbankmanagementsystem für eine Buchtauschplattform.
Ziel ist es, reale Geschäftsprozesse wie das Anbieten, Ausleihen und Bewerten von Büchern effizient und konsistent abzubilden.

Ein zentrales Designmerkmal ist die Trennung zwischen:

* **BOOK (logisches Buchwerk)**
* **USER_BOOK (physisches Exemplar eines Buches)**

Diese Modellierung reduziert Redundanzen und ermöglicht eine flexible Erweiterung des Systems.

---

##  Systemarchitektur

Die Datenbank basiert auf einem Entity-Relationship-Modell und wurde vollständig in ein relationales Schema überführt.

### Wichtige Entitäten:

* `USER` – Benutzer der Plattform
* `ADDRESS` – Adressdaten
* `BOOK` – logische Bücher
* `USER_BOOK` – physische Exemplare
* `LOAN` – Ausleihvorgänge
* `REVIEW` – Bewertungen
* `AVAILABILITY` – Verfügbarkeiten (ternäre Beziehung)

---

## ⚙️ Funktionalitäten

Das System unterstützt folgende Kernfunktionen:

*  **Suche nach verfügbaren Büchern**
*  **Verwaltung von Buchangeboten**
*  **Ausleihe von Büchern (inkl. Status-Tracking)**
*  **Bewertung von ausgeliehenen Büchern**
*  **Zeitfenster-basierte Abholung (Time Slots)**

---

##  Datenbankdesign & Konzepte

* Verwendung von **UUIDs** als Primärschlüssel
* Einsatz von **ENUM-Typen** für Status und Rollen
* Umsetzung von **1:N und N:M Beziehungen**
* Modellierung von **ternären Beziehungen** (`AVAILABILITY`, `LOAN`)
* Einhaltung der **3. Normalform (3NF)**

---

##  Performance & Optimierung

Zur Verbesserung der Performance wurden folgende Maßnahmen umgesetzt:

* 🔹 **Indizes auf Foreign Keys**
* 🔹 **Zusammengesetzte Indizes (Composite Indexes)**
* 🔹 **Partielle Indizes für häufige Abfragen**
* 🔹 Optimierung von SQL-Abfragen durch **JOIN statt Subqueries**

---

##  Datenintegrität

Zur Sicherstellung der Datenqualität wurden folgende Mechanismen implementiert:

* ✔️ `CHECK`-Constraints (z. B. Rating 1–5)
* ✔️ `UNIQUE`-Constraints (z. B. ein Review pro Loan)
* ✔️ `FOREIGN KEY`-Constraints
* ✔️ Business-Regeln (z. B. keine Doppelbuchung)

---

## 🧪 Tests & Validierung

Das System wurde anhand mehrerer Testfälle überprüft:

* Anzeige verfügbarer Bücher
* Auswertung von Ausleihvorgängen
* Aggregationen (z. B. Durchschnittsbewertung)
* Validierung von Constraints durch Fehlereingaben

---

## 🛠️ Technologien

* **PostgreSQL**
* **pgAdmin**
* SQL (DDL, DML, Constraints, Indizes)

---

## 📥 Installation

1. PostgreSQL installieren  
2. pgAdmin starten  
3. Neue Datenbank erstellen  
4. SQL-Skript ausführen:
   ```sql
   buchtausch_app.sql

---

## 📊 Metadaten

* Anzahl der Tabellen: **12**
* Anzahl der Datensätze: **> 120**
* Datenbankgröße: **im MB-Bereich**

---

## 👨‍💻 Autor

**Abdelrahman Baraka**

---

