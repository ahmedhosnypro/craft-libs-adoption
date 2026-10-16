# Sequence diagrams

Sequence diagrams show interactions between participants over time. Use them for API flows, authentication sequences, and system component interactions.

## Basic syntax

```mermaid
sequenceDiagram
    participant A
    participant B
    A->>B: Message
```

## Participants and actors

```mermaid
sequenceDiagram
    actor User
    participant Frontend
    participant API
    participant Database

    User->>Frontend: Click button
    Frontend->>API: POST /data
```

- `participant` — system components (services, classes, databases)
- `actor` — external entities (users, external systems); drawn with a stick figure

Lifelines appear in the order participants are first referenced. Declare every participant with an explicit `participant`/`actor` line before the first message to control the display order. Order them logically, typically: user, frontend, backend, database.

Give a participant a display name with `participant A as Service A`.

## Message types

```mermaid
sequenceDiagram
    Client->>Server: Request
    Server-->>Client: Response
    Server-)Queue: Async message
    Queue--)Client: Async response
    Client-xServer: Delete
```

- `->>` — solid arrow (request)
- `-->>` — dotted arrow (response/return)
- `-)` — solid open arrow (asynchronous, fire-and-forget)
- `--)` — dotted open arrow (asynchronous response)
- `-x` — cross-ended arrow; the message never reaches its target (lost or delete)

A participant can message itself (`API->>API: Verify token`) to show local processing.

## Activations

Activation bars show when a participant is actively processing a request:

```mermaid
sequenceDiagram
    Client->>+Server: Request
    Server->>+Database: Query
    Database-->>-Server: Data
    Server-->>-Client: Response
```

- `+` after the arrow target activates the lifeline
- `-` after the arrow target deactivates it

## Message numbering

Put `autonumber` before the first message to number messages automatically:

```mermaid
sequenceDiagram
    autonumber

    User->>Frontend: Login
    Frontend->>API: Authenticate
    API-->>Frontend: JWT token
    Frontend-->>User: Success
```

## Interaction fragments

Every fragment opens with its keyword plus a free-text condition and closes with `end`. Fragments nest.

### `alt`/`else` — conditional branches

```mermaid
sequenceDiagram
    User->>API: POST /login

    alt Valid credentials
        API-->>User: 200 OK + Token
    else Invalid credentials
        API-->>User: 401 Unauthorized
    else Account locked
        API-->>User: 403 Forbidden
    end
```

### `opt` — optional steps

```mermaid
sequenceDiagram
    User->>API: POST /order
    API->>PaymentService: Process payment

    opt Payment successful
        API->>EmailService: Send confirmation
    end

    API-->>User: Order result
```

### `par`/`and` — parallel operations

```mermaid
sequenceDiagram
    API->>Service: Process order

    par Send email
        Service->>EmailService: Send confirmation
    and Update inventory
        Service->>InventoryService: Reduce stock
    end

    Service-->>API: Complete
```

Each `and` section runs concurrently; execution continues after `end` once all sections finish.

### `loop` — repetition

The label is free text describing the condition:

```mermaid
sequenceDiagram
    Client->>Server: Request batch

    loop For each item
        Server->>Database: Process item
        Database-->>Server: Result
    end

    Server-->>Client: All results
```

```mermaid
sequenceDiagram
    loop Every 5 seconds
        Monitor->>API: Health check
        API-->>Monitor: Status
    end
```

### `break` — early exit

On the condition, the flow stops and the remaining messages after the block are skipped:

```mermaid
sequenceDiagram
    User->>API: Submit form
    API->>Validator: Validate input

    break Input invalid
        API-->>User: 400 Bad Request
    end

    API->>Database: Save data
    Database-->>API: Success
    API-->>User: 200 OK
```

### `critical` — critical region with fallbacks

The critical section must succeed; each `option` describes a fallback for a handled failure:

```mermaid
sequenceDiagram
    Service->>+DB: Connect

    critical Connection must succeed
        DB-->>Service: Connected
    option Network timeout
        Service->>DB: Reconnect
        DB-->>Service: Connected
    end
```

## Notes

Attach notes to lifelines with `Note over`, `Note right of`, and `Note left of`. `Note over` accepts a comma-separated span:

```mermaid
sequenceDiagram
    User->>API: Request
    Note left of User: Updates UI
    Note over API: Validates JWT token
    Note over User,API: HTTPS encrypted
    API-->>User: Response
    Note right of API: Logs to database
```

## Links

Attach clickable links to a participant with `link`; repeat for multiple links:

```mermaid
sequenceDiagram
    participant A as Service A
    link A: Dashboard @ https://dashboard.example.com
    link A: API Docs @ https://docs.example.com

    A->>B: Message
```

## Comprehensive example: authentication flow

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Frontend
    participant AuthAPI
    participant Database
    participant Redis
    participant EmailService

    User->>+Frontend: Enter credentials
    Frontend->>+AuthAPI: POST /auth/login

    AuthAPI->>+Database: Query user by email
    Database-->>-AuthAPI: User record

    alt User not found
        AuthAPI-->>Frontend: 404 User not found
        Frontend-->>User: Show error
    else User found
        AuthAPI->>AuthAPI: Verify password hash

        alt Invalid password
            AuthAPI->>Database: Increment failed attempts

            opt Failed attempts > 5
                AuthAPI->>Database: Lock account
                AuthAPI->>EmailService: Send security alert
            end

            AuthAPI-->>Frontend: 401 Invalid credentials
            Frontend-->>User: Show error
        else Valid password
            AuthAPI->>AuthAPI: Generate JWT token
            AuthAPI->>+Redis: Store session
            Redis-->>-AuthAPI: Confirm

            par Update login metadata
                AuthAPI->>Database: Update last_login
            and Track analytics
                AuthAPI->>Database: Log login event
            end

            AuthAPI-->>-Frontend: 200 OK + JWT token
            Frontend->>Frontend: Store token in localStorage
            Frontend-->>-User: Redirect to dashboard
        end
    end
```

## Best practices

1. Order participants logically: user, frontend, backend, database.
2. Use activations to show when components are actively processing.
3. Group related logic with `alt`/`opt`/`par`/`loop`.
4. Add notes to explain complex logic or important details.
5. Keep one scenario per diagram.
6. Use `autonumber` for complex flows.
7. Show error paths with `alt`/`else` branches.
8. Use open arrows (`-)`, `--)`) for fire-and-forget asynchronous messages.

## Common use cases

- **Authentication** — login, OAuth/SSO, token refresh, password reset
- **API operations** — CRUD, search and filtering, batch processing, webhook handling
- **System integration** — microservice communication, third-party API calls, message queues, event-driven architecture
- **Business processes** — order fulfillment, payment processing, approval workflows, notification chains
