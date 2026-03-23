
-- ============================================================
-- Phase 2 – Buchtausch-App (PostgreSQL)
-- 
--
-- Verbesserungen:
-- 1) Erweiterte Kommentierung komplexer Designentscheidungen
-- 2) Zusätzliche Constraints zur Sicherung der Datenintegrität
-- 3) Trigger für automatische Pflege von updated_at
-- 4) Trigger für zentrale Business-Regeln bei Ausleihen
-- 5) Zusätzliche zusammengesetzte und partielle Indizes
-- 6) Optimierte Insert-Statements mit JOINs statt vieler Subqueries
-- 7) Erweiterte Testabfragen für realistische Prüfszenarien
-- ============================================================

-- ------------------------------------------------------------
-- 0) Erweiterungen
-- ------------------------------------------------------------

-- pgcrypto wird für gen_random_uuid() benötigt.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- 1) ENUM-Typen
-- ------------------------------------------------------------

-- Benutzerrollen innerhalb der Anwendung
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE user_role AS ENUM ('USER', 'ADMIN');
  END IF;
END $$;

-- Kontostatus eines Benutzers
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_status') THEN
    CREATE TYPE user_status AS ENUM ('ACTIVE', 'BLOCKED', 'DELETED');
  END IF;
END $$;

-- Status eines Ausleihvorgangs
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'loan_status') THEN
    CREATE TYPE loan_status AS ENUM (
      'REQUESTED',
      'APPROVED',
      'REJECTED',
      'ACTIVE',
      'RETURNED',
      'CANCELLED'
    );
  END IF;
END $$;

-- ------------------------------------------------------------
-- 2) Vorhandene Trigger/Funktionen entfernen (für Wiederholbarkeit)
-- ------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_user_set_updated_at ON "user";
DROP TRIGGER IF EXISTS trg_validate_loan_business_rules ON loan;

DROP FUNCTION IF EXISTS set_updated_at();
DROP FUNCTION IF EXISTS validate_loan_business_rules();

-- ------------------------------------------------------------
-- 3) Tabellen löschen (für Wiederholbarkeit)
-- ------------------------------------------------------------

DROP TABLE IF EXISTS review CASCADE;
DROP TABLE IF EXISTS loan CASCADE;
DROP TABLE IF EXISTS availability CASCADE;
DROP TABLE IF EXISTS pickup_location CASCADE;
DROP TABLE IF EXISTS time_slot CASCADE;
DROP TABLE IF EXISTS user_book CASCADE;
DROP TABLE IF EXISTS book CASCADE;
DROP TABLE IF EXISTS author CASCADE;
DROP TABLE IF EXISTS genre CASCADE;
DROP TABLE IF EXISTS publisher CASCADE;
DROP TABLE IF EXISTS "user" CASCADE;
DROP TABLE IF EXISTS address CASCADE;

-- ------------------------------------------------------------
-- 4) Tabellen erstellen
-- ------------------------------------------------------------

-- 4.1 ADDRESS
-- Speichert Adressdaten von Benutzern und Abholorten.
-- latitude/longitude sind optional, aber bei Speicherung auf valide Werte begrenzt.
CREATE TABLE address (
  address_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  street       VARCHAR(200) NOT NULL,
  postal_code  VARCHAR(20)  NOT NULL,
  city         VARCHAR(100) NOT NULL,
  country      VARCHAR(100) NOT NULL,
  latitude     DECIMAL(9,6),
  longitude    DECIMAL(9,6),

  CONSTRAINT chk_address_latitude
    CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),

  CONSTRAINT chk_address_longitude
    CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

-- 4.2 USER
-- "user" ist in PostgreSQL ein reservierungsnaher Name, deshalb in Anführungszeichen.
-- updated_at wird über einen Trigger automatisch gepflegt.
CREATE TABLE "user" (
  user_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         VARCHAR(150) NOT NULL,
  email        VARCHAR(200) NOT NULL UNIQUE,
  phone        VARCHAR(50),
  role         user_role NOT NULL DEFAULT 'USER',
  status       user_status NOT NULL DEFAULT 'ACTIVE',
  address_id   UUID REFERENCES address(address_id) ON DELETE SET NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMP NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_user_email_format
    CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- 4.3 AUTHOR
CREATE TABLE author (
  author_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name      VARCHAR(200) NOT NULL UNIQUE
);

-- 4.4 GENRE
CREATE TABLE genre (
  genre_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name     VARCHAR(100) NOT NULL UNIQUE
);

-- 4.5 PUBLISHER
CREATE TABLE publisher (
  publisher_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         VARCHAR(200) NOT NULL UNIQUE
);

-- 4.6 BOOK
-- BOOK repräsentiert das logische Werk, nicht das physische Exemplar.
-- Dadurch werden Redundanzen vermieden, weil Metadaten wie Titel, Autor,
-- Genre und Verlag nur einmal gepflegt werden müssen.
CREATE TABLE book (
  book_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title             VARCHAR(300) NOT NULL,
  publication_year  INT,
  language          VARCHAR(50),
  author_id         UUID NOT NULL REFERENCES author(author_id) ON DELETE RESTRICT,
  genre_id          UUID NOT NULL REFERENCES genre(genre_id) ON DELETE RESTRICT,
  publisher_id      UUID NOT NULL REFERENCES publisher(publisher_id) ON DELETE RESTRICT,

  CONSTRAINT chk_book_publication_year
    CHECK (publication_year IS NULL OR publication_year BETWEEN 1400 AND 2100),

  CONSTRAINT uq_book_logical_work
    UNIQUE (title, author_id, publisher_id, publication_year)
);

-- 4.7 USER_BOOK
-- USER_BOOK repräsentiert das physische Exemplar eines Buches, das einem
-- konkreten Benutzer gehört. Diese Trennung zwischen BOOK (Werk) und USER_BOOK
-- (Exemplar) ist zentral für die Normalisierung und vermeidet Datenredundanz.
CREATE TABLE user_book (
  user_book_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES "user"(user_id) ON DELETE CASCADE,
  book_id           UUID NOT NULL REFERENCES book(book_id) ON DELETE CASCADE,
  condition         VARCHAR(100),
  max_loan_days     INT,
  comment           TEXT,
  shipping_option   BOOLEAN NOT NULL DEFAULT FALSE,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMP NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_user_book_condition
    CHECK (
      condition IS NULL OR
      condition IN ('Very Good', 'Good', 'Acceptable', 'Poor')
    ),

  CONSTRAINT chk_user_book_max_loan_days
    CHECK (max_loan_days IS NULL OR max_loan_days BETWEEN 1 AND 365)
);

-- 4.8 PICKUP_LOCATION
-- Ein Benutzer kann mehrere Abholorte definieren.
CREATE TABLE pickup_location (
  location_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES "user"(user_id) ON DELETE CASCADE,
  address_id   UUID NOT NULL REFERENCES address(address_id) ON DELETE RESTRICT,
  description  VARCHAR(200),
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 4.9 TIME_SLOT
-- Zeitfenster für Verfügbarkeiten und Ausleihen.
CREATE TABLE time_slot (
  timeslot_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  start_time  TIMESTAMP NOT NULL,
  end_time    TIMESTAMP NOT NULL,

  CONSTRAINT chk_timeslot_valid
    CHECK (end_time > start_time)
);

-- 4.10 AVAILABILITY
-- Ternäre Beziehung zwischen Exemplar, Abholort und Zeitfenster.
-- Die Kombination aus user_book, location und timeslot darf nur einmal vorkommen,
-- um redundante Verfügbarkeitsdaten zu verhindern.
CREATE TABLE availability (
  availability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_book_id    UUID NOT NULL REFERENCES user_book(user_book_id) ON DELETE CASCADE,
  location_id     UUID NOT NULL REFERENCES pickup_location(location_id) ON DELETE CASCADE,
  timeslot_id     UUID NOT NULL REFERENCES time_slot(timeslot_id) ON DELETE CASCADE,
  is_available    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMP NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_availability
    UNIQUE (user_book_id, location_id, timeslot_id)
);

-- 4.11 LOAN
-- Ternäre Beziehung zwischen Entleiher, Exemplar und Zeitfenster.
-- Die Fachlogik wird zusätzlich durch Trigger abgesichert.
CREATE TABLE loan (
  loan_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_book_id  UUID NOT NULL REFERENCES user_book(user_book_id) ON DELETE CASCADE,
  borrower_id   UUID NOT NULL REFERENCES "user"(user_id) ON DELETE RESTRICT,
  timeslot_id   UUID NOT NULL REFERENCES time_slot(timeslot_id) ON DELETE RESTRICT,

  status        loan_status NOT NULL DEFAULT 'REQUESTED',
  requested_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  approved_at   TIMESTAMP,
  loan_start    DATE,
  due_date      DATE,
  return_date   DATE,

  CONSTRAINT chk_loan_dates
    CHECK (
      (loan_start IS NULL OR due_date IS NULL OR due_date >= loan_start)
      AND
      (return_date IS NULL OR loan_start IS NULL OR return_date >= loan_start)
    ),

  CONSTRAINT chk_loan_approved_after_requested
    CHECK (approved_at IS NULL OR approved_at >= requested_at)
);

-- Dieser Unique Index verhindert, dass dasselbe physische Exemplar
-- im selben Zeitfenster mehrfach ausgeliehen wird.
CREATE UNIQUE INDEX uq_loan_userbook_timeslot
ON loan(user_book_id, timeslot_id);

-- 4.12 REVIEW
-- Pro Ausleihe ist maximal eine Bewertung erlaubt.
CREATE TABLE review (
  review_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id       UUID NOT NULL UNIQUE REFERENCES loan(loan_id) ON DELETE CASCADE,
  reviewer_id   UUID NOT NULL REFERENCES "user"(user_id) ON DELETE RESTRICT,
  rating        INT NOT NULL,
  comment       TEXT,
  created_at    TIMESTAMP NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_review_rating
    CHECK (rating BETWEEN 1 AND 5)
);

-- ------------------------------------------------------------
-- 5) Trigger-Funktionen
-- ------------------------------------------------------------

-- 5.1 updated_at automatisch setzen
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_set_updated_at
BEFORE UPDATE ON "user"
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- 5.2 Business-Regeln für LOAN validieren
-- Diese Regeln können nicht sinnvoll nur per CHECK Constraint geprüft werden,
-- da dafür auf Daten anderer Tabellen zugegriffen werden muss.
CREATE OR REPLACE FUNCTION validate_loan_business_rules()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_id UUID;
  v_max_loan_days INT;
BEGIN
  -- Eigentümer des Exemplars bestimmen
  SELECT ub.user_id, ub.max_loan_days
  INTO v_owner_id, v_max_loan_days
  FROM user_book ub
  WHERE ub.user_book_id = NEW.user_book_id;

  -- Entleiher darf nicht zugleich Eigentümer sein
  IF NEW.borrower_id = v_owner_id THEN
    RAISE EXCEPTION 'Ein Benutzer darf sein eigenes Buch nicht ausleihen.';
  END IF;

  -- Statusabhängige Plausibilitätsprüfung
  IF NEW.status IN ('APPROVED', 'ACTIVE', 'RETURNED') AND NEW.approved_at IS NULL THEN
    RAISE EXCEPTION 'approved_at muss bei APPROVED, ACTIVE oder RETURNED gesetzt sein.';
  END IF;

  IF NEW.status IN ('ACTIVE', 'RETURNED') AND NEW.loan_start IS NULL THEN
    RAISE EXCEPTION 'loan_start muss bei ACTIVE oder RETURNED gesetzt sein.';
  END IF;

  IF NEW.status IN ('ACTIVE', 'RETURNED') AND NEW.due_date IS NULL THEN
    RAISE EXCEPTION 'due_date muss bei ACTIVE oder RETURNED gesetzt sein.';
  END IF;

  IF NEW.status = 'RETURNED' AND NEW.return_date IS NULL THEN
    RAISE EXCEPTION 'return_date muss bei RETURNED gesetzt sein.';
  END IF;

  -- due_date optional fachlich mit max_loan_days abgleichen, falls gesetzt
  IF NEW.loan_start IS NOT NULL
     AND NEW.due_date IS NOT NULL
     AND v_max_loan_days IS NOT NULL
     AND NEW.due_date > (NEW.loan_start + v_max_loan_days) THEN
    RAISE EXCEPTION 'due_date überschreitet max_loan_days des Exemplars.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_loan_business_rules
BEFORE INSERT OR UPDATE ON loan
FOR EACH ROW
EXECUTE FUNCTION validate_loan_business_rules();

-- ------------------------------------------------------------
-- 6) Indizes (Performance-Optimierung)
-- ------------------------------------------------------------

-- Standardindizes auf Fremdschlüsselspalten
CREATE INDEX idx_user_address_id              ON "user"(address_id);

CREATE INDEX idx_book_author_id               ON book(author_id);
CREATE INDEX idx_book_genre_id                ON book(genre_id);
CREATE INDEX idx_book_publisher_id            ON book(publisher_id);

CREATE INDEX idx_user_book_user_id            ON user_book(user_id);
CREATE INDEX idx_user_book_book_id            ON user_book(book_id);

CREATE INDEX idx_pickup_location_user_id      ON pickup_location(user_id);
CREATE INDEX idx_pickup_location_address_id   ON pickup_location(address_id);

CREATE INDEX idx_availability_user_book_id    ON availability(user_book_id);
CREATE INDEX idx_availability_location_id     ON availability(location_id);
CREATE INDEX idx_availability_timeslot_id     ON availability(timeslot_id);

CREATE INDEX idx_loan_user_book_id            ON loan(user_book_id);
CREATE INDEX idx_loan_borrower_id             ON loan(borrower_id);
CREATE INDEX idx_loan_timeslot_id             ON loan(timeslot_id);
CREATE INDEX idx_review_reviewer_id           ON review(reviewer_id);

-- Zusätzliche Indizes gemäß Tutor-Feedback:
-- zusammengesetzte und partielle Indizes für häufige Filter- und Join-Muster

-- Hilft bei Suchen nach Stadt
CREATE INDEX idx_address_city
ON address(city);

-- Hilft bei kombinierten Zugriffen auf owner + Werk
CREATE INDEX idx_user_book_user_book
ON user_book(user_id, book_id);

-- Hilft bei Filtern nach verfügbar/nicht verfügbar
CREATE INDEX idx_availability_is_available_user_book
ON availability(is_available, user_book_id);

-- Hilft bei Borrower-Abfragen inkl. Status
CREATE INDEX idx_loan_borrower_status
ON loan(borrower_id, status);

-- Hilft bei Sortierung/Filterung nach Status und Anfragezeitpunkt
CREATE INDEX idx_loan_status_requested_at
ON loan(status, requested_at DESC);

-- Partieller Index für häufigen Praxisfall "aktive Ausleihen"
CREATE INDEX idx_loan_active_user_book
ON loan(user_book_id)
WHERE status = 'ACTIVE';

-- Partieller Index für Rückgaben
CREATE INDEX idx_loan_returned_return_date
ON loan(return_date)
WHERE status = 'RETURNED';

-- ------------------------------------------------------------
-- 7) Dummy-Daten (jede Tabelle mindestens 10 Einträge)
-- ------------------------------------------------------------

-- 7.1 ADDRESS (10)
INSERT INTO address(street, postal_code, city, country, latitude, longitude)
SELECT
  'Musterstraße ' || gs,
  '10' || LPAD(gs::text, 3, '0'),
  CASE WHEN gs <= 5 THEN 'Berlin' ELSE 'München' END,
  'Deutschland',
  52.520000 + (gs * 0.001),
  13.405000 + (gs * 0.001)
FROM generate_series(1,10) AS gs;

-- 7.2 USER (10 reguläre Benutzer)
-- User i wird mit Address i verknüpft.
INSERT INTO "user"(name, email, phone, role, status, address_id)
SELECT
  'User ' || gs,
  'user' || gs || '@example.com',
  '+49-170-0000' || LPAD(gs::text, 2, '0'),
  'USER'::user_role,
  'ACTIVE'::user_status,
  a.address_id
FROM generate_series(1,10) AS gs
JOIN address a
  ON a.postal_code = ('10' || LPAD(gs::text, 3, '0'));

-- 1 Admin zusätzlich
INSERT INTO "user"(name, email, phone, role, status, address_id)
SELECT
  'Admin 1',
  'admin1@example.com',
  '+49-170-999999',
  'ADMIN'::user_role,
  'ACTIVE'::user_status,
  a.address_id
FROM address a
ORDER BY a.postal_code
LIMIT 1;

-- 7.3 AUTHOR (10)
INSERT INTO author(name)
SELECT 'Author ' || gs
FROM generate_series(1,10) AS gs;

-- 7.4 GENRE (10)
INSERT INTO genre(name)
SELECT 'Genre ' || gs
FROM generate_series(1,10) AS gs;

-- 7.5 PUBLISHER (10)
INSERT INTO publisher(name)
SELECT 'Publisher ' || gs
FROM generate_series(1,10) AS gs;

-- 7.6 BOOK (10)
-- Optimiert: JOINs statt mehrerer korrelierter Subqueries
INSERT INTO book(title, publication_year, language, author_id, genre_id, publisher_id)
SELECT
  'Book Title ' || gs,
  2000 + gs,
  CASE WHEN gs % 2 = 0 THEN 'DE' ELSE 'EN' END,
  a.author_id,
  g.genre_id,
  p.publisher_id
FROM generate_series(1,10) AS gs
JOIN author a
  ON a.name = 'Author ' || gs
JOIN genre g
  ON g.name = 'Genre ' || gs
JOIN publisher p
  ON p.name = 'Publisher ' || gs;

-- 7.7 USER_BOOK (10)
-- User i besitzt Exemplar von Book i
INSERT INTO user_book(user_id, book_id, condition, max_loan_days, comment, shipping_option, is_active)
SELECT
  u.user_id,
  b.book_id,
  CASE
    WHEN gs % 4 = 0 THEN 'Poor'
    WHEN gs % 4 = 1 THEN 'Very Good'
    WHEN gs % 4 = 2 THEN 'Good'
    ELSE 'Acceptable'
  END,
  14 + gs,
  'Kommentar Exemplar ' || gs,
  (gs % 2 = 0),
  TRUE
FROM generate_series(1,10) AS gs
JOIN "user" u
  ON u.email = 'user' || gs || '@example.com'
JOIN book b
  ON b.title = 'Book Title ' || gs;

-- 7.8 PICKUP_LOCATION (10)
INSERT INTO pickup_location(user_id, address_id, description, is_active)
SELECT
  u.user_id,
  a.address_id,
  'Abholort ' || gs,
  TRUE
FROM generate_series(1,10) AS gs
JOIN "user" u
  ON u.email = 'user' || gs || '@example.com'
JOIN address a
  ON a.postal_code = ('10' || LPAD(gs::text, 3, '0'));

-- 7.9 TIME_SLOT (10)
-- 10 Zeitfenster à 2 Stunden, beginnend morgen um 10:00 Uhr
INSERT INTO time_slot(start_time, end_time)
SELECT
  (date_trunc('day', NOW()) + INTERVAL '1 day' + INTERVAL '10 hour') + (gs - 1) * INTERVAL '3 hour',
  (date_trunc('day', NOW()) + INTERVAL '1 day' + INTERVAL '12 hour') + (gs - 1) * INTERVAL '3 hour'
FROM generate_series(1,10) AS gs;

-- 7.10 AVAILABILITY (10)
-- Optimiert mit CTEs und JOINs statt mehrfacher Unterabfragen
WITH numbered_user_books AS (
  SELECT
    ub.user_book_id,
    u.email,
    b.title,
    ROW_NUMBER() OVER (ORDER BY u.email, b.title) AS rn
  FROM user_book ub
  JOIN "user" u ON u.user_id = ub.user_id
  JOIN book b ON b.book_id = ub.book_id
),
numbered_pickup_locations AS (
  SELECT
    pl.location_id,
    u.email,
    pl.description,
    ROW_NUMBER() OVER (ORDER BY u.email, pl.description) AS rn
  FROM pickup_location pl
  JOIN "user" u ON u.user_id = pl.user_id
),
numbered_time_slots AS (
  SELECT
    ts.timeslot_id,
    ROW_NUMBER() OVER (ORDER BY ts.start_time) AS rn
  FROM time_slot ts
)
INSERT INTO availability(user_book_id, location_id, timeslot_id, is_available)
SELECT
  nub.user_book_id,
  npl.location_id,
  nts.timeslot_id,
  TRUE
FROM generate_series(1,10) AS gs
JOIN numbered_user_books nub
  ON nub.email = 'user' || gs || '@example.com'
 AND nub.title = 'Book Title ' || gs
JOIN numbered_pickup_locations npl
  ON npl.email = 'user' || gs || '@example.com'
 AND npl.description = 'Abholort ' || gs
JOIN numbered_time_slots nts
  ON nts.rn = gs;

-- 7.11 LOAN (10)
-- borrower = user(i+1), damit owner != borrower
WITH numbered_time_slots AS (
  SELECT
    ts.timeslot_id,
    ROW_NUMBER() OVER (ORDER BY ts.start_time) AS rn
  FROM time_slot ts
)
INSERT INTO loan(
  user_book_id,
  borrower_id,
  timeslot_id,
  status,
  requested_at,
  approved_at,
  loan_start,
  due_date,
  return_date
)
SELECT
  ub.user_book_id,
  borrower.user_id,
  nts.timeslot_id,
  CASE
    WHEN gs <= 3 THEN 'REQUESTED'::loan_status
    WHEN gs <= 6 THEN 'APPROVED'::loan_status
    WHEN gs <= 8 THEN 'RETURNED'::loan_status
    ELSE 'ACTIVE'::loan_status
  END,
  NOW() - (gs * INTERVAL '1 day'),
  CASE WHEN gs > 3 THEN NOW() - ((gs - 1) * INTERVAL '1 day') ELSE NULL END,
  CASE WHEN gs >= 7 THEN (CURRENT_DATE - gs) ELSE NULL END,
  CASE WHEN gs >= 7 THEN (CURRENT_DATE - gs) + (7 + gs) ELSE NULL END,
  CASE WHEN gs BETWEEN 7 AND 8 THEN (CURRENT_DATE - (gs - 2)) ELSE NULL END
FROM generate_series(1,10) AS gs
JOIN "user" owner
  ON owner.email = 'user' || gs || '@example.com'
JOIN user_book ub
  ON ub.user_id = owner.user_id
JOIN book b
  ON b.book_id = ub.book_id
 AND b.title = 'Book Title ' || gs
JOIN "user" borrower
  ON borrower.email = 'user' || (CASE WHEN gs = 10 THEN 1 ELSE gs + 1 END) || '@example.com'
JOIN numbered_time_slots nts
  ON nts.rn = gs;

-- 7.12 REVIEW (10)
-- Jede Ausleihe erhält genau ein Review.
INSERT INTO review(loan_id, reviewer_id, rating, comment)
SELECT
  l.loan_id,
  l.borrower_id,
  (1 + (ROW_NUMBER() OVER (ORDER BY l.requested_at)) % 5),
  'Review zu Loan ' || ROW_NUMBER() OVER (ORDER BY l.requested_at)
FROM loan l
ORDER BY l.requested_at
LIMIT 10;

-- ------------------------------------------------------------
-- 8) Testfälle / Validierungsabfragen
-- ------------------------------------------------------------

-- TEST 1:
-- Verfügbare Exemplare in Berlin inkl. Buchinfo + Zeitfenster
-- Prüft JOINs zwischen Verfügbarkeit, Exemplar, Besitzer, Abholort und Adresse.
SELECT
  b.title,
  u.name AS owner,
  a.city,
  pl.description,
  ts.start_time,
  ts.end_time,
  av.is_available
FROM availability av
JOIN user_book ub      ON ub.user_book_id = av.user_book_id
JOIN "user" u          ON u.user_id = ub.user_id
JOIN book b            ON b.book_id = ub.book_id
JOIN pickup_location pl ON pl.location_id = av.location_id
JOIN address a         ON a.address_id = pl.address_id
JOIN time_slot ts      ON ts.timeslot_id = av.timeslot_id
WHERE a.city = 'Berlin'
  AND av.is_available = TRUE
ORDER BY ts.start_time;

-- TEST 2:
-- Alle Ausleihen eines bestimmten Borrowers mit Status und Daten
SELECT
  borrower.email AS borrower,
  b.title,
  l.status,
  l.requested_at,
  l.loan_start,
  l.due_date,
  l.return_date
FROM loan l
JOIN "user" borrower ON borrower.user_id = l.borrower_id
JOIN user_book ub    ON ub.user_book_id = l.user_book_id
JOIN book b          ON b.book_id = ub.book_id
WHERE borrower.email = 'user2@example.com'
ORDER BY l.requested_at DESC;

-- TEST 3:
-- Prüfung, dass pro Loan maximal ein Review existiert
-- Ergebnis soll leer sein.
SELECT
  loan_id,
  COUNT(*) AS reviews_per_loan
FROM review
GROUP BY loan_id
HAVING COUNT(*) > 1;

-- TEST 4:
-- Durchschnittliche Bewertung pro Besitzer des Exemplars
SELECT
  owner.email AS owner,
  ROUND(AVG(r.rating)::numeric, 2) AS avg_rating,
  COUNT(*) AS review_count
FROM review r
JOIN loan l      ON l.loan_id = r.loan_id
JOIN user_book ub ON ub.user_book_id = l.user_book_id
JOIN "user" owner ON owner.user_id = ub.user_id
GROUP BY owner.email
ORDER BY avg_rating DESC, review_count DESC;

-- TEST 5:
-- Beispiel-Update: Eine aktive Ausleihe wird als RETURNED markiert
-- und mit einem Rückgabedatum versehen.
UPDATE loan
SET status = 'RETURNED',
    return_date = CURRENT_DATE
WHERE loan_id = (
  SELECT loan_id
  FROM loan
  WHERE status = 'ACTIVE'
  ORDER BY requested_at
  LIMIT 1
);

SELECT
  loan_id,
  status,
  return_date
FROM loan
ORDER BY requested_at DESC;

-- TEST 6:
-- Overdue-Prüfung: Welche Ausleihen sind überfällig?
SELECT
  l.loan_id,
  borrower.email AS borrower,
  b.title,
  l.loan_start,
  l.due_date,
  CURRENT_DATE - l.due_date AS overdue_days
FROM loan l
JOIN "user" borrower ON borrower.user_id = l.borrower_id
JOIN user_book ub    ON ub.user_book_id = l.user_book_id
JOIN book b          ON b.book_id = ub.book_id
WHERE l.status = 'ACTIVE'
  AND l.due_date < CURRENT_DATE
ORDER BY overdue_days DESC;

-- TEST 7:
-- Zeigt, wie viele physische Exemplare je Stadt verfügbar sind.
SELECT
  a.city,
  COUNT(*) AS available_copies
FROM availability av
JOIN pickup_location pl ON pl.location_id = av.location_id
JOIN address a          ON a.address_id = pl.address_id
WHERE av.is_available = TRUE
GROUP BY a.city
ORDER BY available_copies DESC;

-- Ende
