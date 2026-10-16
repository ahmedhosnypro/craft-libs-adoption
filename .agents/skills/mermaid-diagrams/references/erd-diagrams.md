# Entity Relationship Diagrams (ERD)

ERDs model database schemas: tables as entities, columns as attributes, and
inter-table relationships, using the `erDiagram` keyword.

## Basic syntax

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
```

Declare entities with no relationship to render them standalone:

```mermaid
erDiagram
    CUSTOMER
    ORDER
```

## Attributes

Attribute lines take the form `type name keys "comment"`; keys and the quoted
comment are optional. The comment is free text for constraints or defaults.

```mermaid
erDiagram
    CUSTOMER {
        int id PK
        string email UK "NOT NULL"
        string name
        string phone
        datetime created_at "DEFAULT NOW()"
    }
```

Supported key markers:

- `PK` - primary key
- `FK` - foreign key
- `UK` - unique key
- `NN` - not null (common convention, not rendered specially)

A column can carry more than one marker (composite keys in a junction table):

```mermaid
erDiagram
    ENROLLMENT {
        uuid student_id FK PK
        uuid course_id FK PK
        date enrolled_date
    }
```

Use standard database types: `int`, `bigint`, `smallint`, `varchar`, `text`,
`char`, `decimal`, `float`, `double`, `boolean`, `date`, `datetime`,
`timestamp`, `json`, `jsonb`, `uuid`, `blob`, `bytea`.

## Relationships

### Cardinality

Each side of the line takes a cardinality marker:

- `||` - exactly one
- `|o` - zero or one
- `}{` - one or many
- `}o` - zero or many

The line itself:

- `--` - non-identifying relationship
- `..` - identifying relationship (rare in practice)

### Common shapes

```mermaid
erDiagram
    %% One-to-one
    USER ||--|| PROFILE : has

    %% One-to-many
    CUSTOMER ||--o{ ORDER : places

    %% Optional on the "one" side
    EMPLOYEE |o--o{ DEPARTMENT : manages

    %% Many-to-many, plus its explicit junction table
    STUDENT }o--o{ COURSE : enrolls
    STUDENT ||--o{ ENROLLMENT : has
    COURSE ||--o{ ENROLLMENT : includes
```

One entity can be the target of several relationships, and the same pair can
appear twice with different labels:

```mermaid
erDiagram
    AUTHOR ||--o{ BOOK : writes
    BOOK }o--|| PUBLISHER : "published by"
    READER }o--o{ BOOK : reads
```

Quote multi-word relationship labels. Unquoted labels must be a single word
(`places`, `has`); `"belongs to"`, `"shipped via"` require the quotes.

## Full schema example

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : "ordered in"
    PRODUCT }o--|| CATEGORY : "belongs to"

    CUSTOMER {
        bigint id PK "AUTO_INCREMENT"
        varchar email UK "NOT NULL"
        varchar name "NOT NULL"
        varchar phone
        timestamp created_at "DEFAULT NOW()"
        timestamp updated_at
    }

    ORDER {
        uuid id PK
        uuid customer_id FK "NOT NULL"
        decimal total "NOT NULL"
        varchar status "NOT NULL"
        timestamp order_date "DEFAULT NOW()"
        timestamp delivered_date
    }

    LINE_ITEM {
        uuid id PK
        uuid order_id FK "NOT NULL"
        uuid product_id FK "NOT NULL"
        int quantity "NOT NULL"
        decimal price_per_unit "NOT NULL"
        decimal subtotal "COMPUTED"
    }

    PRODUCT {
        uuid id PK
        varchar sku UK "NOT NULL"
        varchar name "NOT NULL"
        text description
        decimal price "NOT NULL"
        uuid category_id FK
        boolean is_active "DEFAULT TRUE"
        timestamp created_at "DEFAULT NOW()"
    }

    CATEGORY {
        uuid id PK
        varchar name UK "NOT NULL"
        text description
        uuid parent_category_id FK
    }
```

The comment slot documents `NOT NULL`, `DEFAULT ...`, `CHECK 1-5`-style
constraints, `COMPUTED` for derived columns, and `NULLABLE` for optional
foreign keys.

## Design patterns

### Self-referencing hierarchy

Point the FK back at the same entity; mark the parent column nullable.

```mermaid
erDiagram
    CATEGORY ||--o{ CATEGORY : "parent of"

    CATEGORY {
        uuid id PK
        varchar name "NOT NULL"
        uuid parent_id FK "NULLABLE"
    }
```

### Junction table

Model many-to-many with an explicit junction entity carrying both `FK PK`
columns as its composite key.

```mermaid
erDiagram
    STUDENT }o--o{ COURSE : enrolls
    STUDENT ||--o{ ENROLLMENT : has
    COURSE ||--o{ ENROLLMENT : includes

    STUDENT {
        uuid id PK
        varchar name "NOT NULL"
    }

    ENROLLMENT {
        uuid student_id FK PK
        uuid course_id FK PK
        date enrolled_date
        varchar grade
    }

    COURSE {
        uuid id PK
        varchar title "NOT NULL"
    }
```

### Polymorphic relationship

A polymorphic target (`commentable_type` + `commentable_id`) has no real FK,
so draw no relationship lines to it; list the entities side by side.

```mermaid
erDiagram
    COMMENT {
        uuid id PK
        uuid user_id FK
        varchar commentable_type "NOT NULL"
        uuid commentable_id "NOT NULL"
        text content
    }

    POST {
        uuid id PK
        varchar title
    }

    VIDEO {
        uuid id PK
        varchar title
    }
```

### Soft deletes

Keep rows and mark deletion with a nullable timestamp instead of a hard
delete.

```mermaid
erDiagram
    USER {
        uuid id PK
        varchar email UK
        varchar name
        timestamp deleted_at "NULLABLE"
    }
```

### Audit trail / versioning

Duplicate critical data into a child version table linked by FK.

```mermaid
erDiagram
    DOCUMENT ||--o{ DOCUMENT_VERSION : has
    DOCUMENT {
        uuid id PK
        varchar title "NOT NULL"
        int current_version "DEFAULT 1"
    }
    DOCUMENT_VERSION {
        uuid id PK
        uuid document_id FK "NOT NULL"
        int version_number "NOT NULL"
        uuid modified_by FK
    }
```

## Authoring conventions

1. Name entities in UPPERCASE.
2. Use singular entity names - `USER` not `USERS`, `ORDER` not `ORDERS`.
3. Define all constraints - document `PK`, `FK`, `UK`, and `NOT NULL`.
4. Show cardinality accurately - do not blur one-to-many and many-to-many.
5. Include `created_at` / `updated_at` timestamps for auditing.
6. Mark computed or derived columns in the comment slot.
7. Quote constraint and description comments.
8. Model many-to-many relationships explicitly with junction tables.
9. Match database-specific types rather than generic ones.
10. Show unique keys (`UK`) beyond the primary key - they are the visible
    index documentation.

## Database design guidance

1. Normalize appropriately - balance normalization against query performance.
2. Use surrogate keys - UUIDs or auto-increment integers as primary keys.
3. Index foreign keys - essential for join performance.
4. Plan for soft deletes - `deleted_at` instead of hard deletes.
5. Version critical data - keep history for important entities.
6. Set appropriate defaults - timestamps, status values, boolean flags.
7. Consider denormalization - counts and cached values for performance.
8. Use enum/check constraints - enforce valid values at the database level.
