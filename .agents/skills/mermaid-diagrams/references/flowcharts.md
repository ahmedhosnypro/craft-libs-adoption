# Flowcharts

Flowcharts visualize processes, algorithms, decision trees, and user journeys. They show step-by-step progression through a system or workflow.

## Basic syntax and directions

```mermaid
flowchart TD
    A --> B
```

Directions: `TD`/`TB` top to bottom (default), `BT` bottom to top, `LR` left to right, `RL` right to left.

## Node shapes

```mermaid
flowchart LR
    A[Rectangle - default]
    B([Rounded rectangle])
    C(Stadium or pill - start and end)
    D[[Subroutine - double border]]
    E[(Cylinder - database)]
    F((Circle))
    G>Asymmetric flag]
    H{Rhombus - decision}
    I{{Hexagon}}
    J[/Parallelogram - input or output/]
    K[\Alternative parallelogram\]
    L[/Trapezoid\]
    M[\Alt trapezoid/]
```

Use consistent shapes: rhombus `{...}` for decisions, stadium `(...)` for start/end nodes, cylinder `[(...)]` for data stores.

## Connections

### Edge types and labels

```mermaid
flowchart LR
    A --> B
    C --- D
    E -->|Label text| F
    G ---|"Text with spaces"| H
    I -.-> J
    K -.- L
    M -.Dotted label.-> N
```

```mermaid
flowchart LR
    A ==> B
    C === D
    E ==Thick label==> F
```

Edge catalog:

- `-->` arrow, `---` open link (no arrow)
- `-->|text|` labeled arrow; quote labels containing spaces: `-->|"Text with spaces"|`
- `-.->` dotted arrow, `-.-` dotted open link, `-.Label.->` dotted with label
- `==>` thick arrow, `===` thick open link, `==Label==>` thick with label

### Chaining and multi-directional links

```mermaid
flowchart LR
    A --> B --> C --> D
    E --> F & G --> H
    I --> J & K & L
    J & K & L --> M
```

`&` fans a single edge out to or in from multiple nodes; chained edges declare a path in one line.

## Subgraphs

```mermaid
flowchart TB
    A[Start]

    subgraph Processing
        B[Step 1]
        C[Step 2]
    end

    E[End]

    A --> B
    C --> E
```

Subgraphs nest and accept their own `direction`:

```mermaid
flowchart LR
    subgraph one
        direction TB
        A1 --> A2

        subgraph Inner
            B1 --> B2
        end
    end

    subgraph two
        direction TB
        C1 --> C2
    end

    one --> two
```

Edges may connect subgraph ids directly (`one --> two`) as well as nodes.

## Styling

### Per-node `style`

```mermaid
flowchart LR
    A[Normal]
    B[Styled]

    style B fill:#ff6b6b,stroke:#333,stroke-width:4px,color:#fff
```

### Classes via `classDef` and `:::`

```mermaid
flowchart LR
    A[Node 1]:::className
    B[Node 2]:::className
    C[Node 3]

    classDef className fill:#f9f,stroke:#333,stroke-width:2px
```

### Link styling via `linkStyle`

```mermaid
flowchart LR
    A --> B

    linkStyle 0 stroke:#ff3,stroke-width:4px,color:red
```

`linkStyle` takes the zero-based edge index. Use `classDef` for repeated styles instead of repeating `style` per node.

## Comprehensive example: decision flow

```mermaid
flowchart TD
    Start([User clicks Checkout]) --> Auth{Authenticated?}

    Auth -->|No| Login[Redirect to login]
    Login --> Auth

    Auth -->|Yes| Cart{Cart empty?}
    Cart -->|Yes| EmptyCart[Show empty cart message]

    Cart -->|No| Address[Show shipping address form]
    Address --> Validate{Valid input?}
    Validate -->|No| Address
    Validate -->|Yes| Process[Process payment]
    Process --> PaymentResult{Payment successful?}

    PaymentResult -->|No| Error[Show payment error]
    Error --> Retry{Retry?}
    Retry -->|No| Cancel([Order cancelled])
    Retry -->|Yes| Process

    PaymentResult -->|Yes| CreateOrder[(Create order record)]
    CreateOrder --> Success([Order complete])

    style Start fill:#90EE90
    style Success fill:#90EE90
    style Cancel fill:#FF6B6B
    style CreateOrder fill:#FFD700
```

## Common patterns

### Linear flow

```mermaid
flowchart LR
    A[Step 1] --> B[Step 2] --> C[Step 3] --> D[Step 4]
```

### Branching decision

```mermaid
flowchart TD
    A[Input] --> B{Condition?}
    B -->|True| C[Path 1]
    B -->|False| D[Path 2]
    C --> E[Merge]
    D --> E
```

### Loop

```mermaid
flowchart TD
    A[Initialize] --> B[Process]
    B --> C{Continue?}
    C -->|Yes| B
    C -->|No| D[Exit]
```

### Error handling with retry

```mermaid
flowchart TD
    A[Try operation] --> B{Success?}
    B -->|Yes| C[Continue]
    B -->|No| D[Handle error]
    D --> E{Retry?}
    E -->|Yes| A
    E -->|No| F[Abort]
```

## Best practices

1. Use meaningful, action-oriented node labels.
2. Use the same shape for the same type of action across the diagram.
3. Model yes/no decisions as diamonds (`{...}`) with labeled exits.
4. Flow top-to-bottom or left-to-right; these match natural reading order.
5. Mark entry and exit points with stadium/pill nodes.
6. Group related steps into subgraphs.
7. Color-code node categories with `classDef`/`style`.
8. Minimize crossing edges by reorganizing nodes.
9. Keep one process per diagram.
