# Buchtausch Database

A PostgreSQL database design for a book-sharing platform. The project models users, physical book copies, availability windows, loans and reviews while enforcing data integrity through constraints and triggers.

## Design focus

A central modeling decision separates:

- `book`: the logical work and its shared metadata
- `user_book`: a physical copy owned by a specific user

This reduces duplicated book metadata and allows several users to offer copies of the same work.

## Main entities

`user`, `address`, `author`, `genre`, `publisher`, `book`, `user_book`, `pickup_location`, `time_slot`, `availability`, `loan` and `review`.

## Implemented database concepts

- UUID primary keys with PostgreSQL `pgcrypto`
- Foreign-key, unique and check constraints
- Enum types for user, account and loan states
- 1:N, N:M and ternary relationships
- Automatic timestamp maintenance with triggers
- Loan business-rule validation
- Composite and partial indexes
- Repeatable setup that recreates the schema
- Sample data and validation queries

## Run the project

Requirements: PostgreSQL with permission to enable `pgcrypto`.

```bash
createdb buchtausch
psql -d buchtausch -f buchtausch_app.sql
```

Alternatively, open `buchtausch_app.sql` in pgAdmin and execute the complete script.

## Documentation

- [SQL implementation](buchtausch_app.sql)
- [Project documentation](Abschluss_Document.pdf)
- [Abstract](Abstract.pdf)
- [Screenshots](Screenshots/)

## Scope and limitations

This repository contains the relational database layer and its documentation, not a complete web application. The business rules demonstrate a possible design for educational purposes and would require additional application-level validation, authentication and operational monitoring in a production system.
