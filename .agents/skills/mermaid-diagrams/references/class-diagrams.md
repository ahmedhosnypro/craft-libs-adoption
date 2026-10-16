# Class diagrams

Class diagrams model object-oriented designs and domain models: entities (classes), their attributes and methods, and the relationships between them.

## Declaring classes

```mermaid
classDiagram
    ClassName
```

Declare members inside a class block:

```mermaid
classDiagram
    class BankAccount {
        +String owner
        +Decimal balance
        -String accountNumber
        +deposit(amount)
        +withdraw(amount)
        +getBalance() Decimal
    }
```

Visibility modifiers:

- `+` Public
- `-` Private
- `#` Protected
- `~` Package/Internal

Member syntax:

- `+type attribute` — attribute with a type
- `+method(params) ReturnType` — method with parameters and return type
- `method()*` — abstract method (trailing asterisk)

## Relationships

| Relationship | Syntax | Meaning |
|---|---|---|
| Association | `--` | Entities use each other but exist independently |
| Directed association | `-->` / `<--` | Association with a navigable direction |
| Composition | `*--` | Strong ownership; deleting the parent deletes the children |
| Aggregation | `o--` | Weak "has-a" ownership; children can exist independently |
| Inheritance | `<|--` | "Is-a"; the child class inherits from the parent |
| Realization | `<|..` | A class implements an interface |
| Dependency | `<..` or `..>` | One class uses another, often as a parameter or local variable |

```mermaid
classDiagram
    Title -- Genre
    Order *-- LineItem
    Department o-- Employee
    Customer --> Order : places
    Animal <|-- Dog
    class Drawable {
        <<interface>>
        +draw()
    }
    Drawable <|.. Circle
    OrderProcessor <.. PaymentGateway
    ShapeFactory ..> Shape : creates
```

## Multiplicity and labels

Show how many instances participate in a relationship; label what the relationship means with `: label`.

```mermaid
classDiagram
    Customer "1" --> "0..*" Order : places
    Order "1" *-- "1..*" LineItem : contains
    Author "1..*" -- "1..*" Book : writes
    Driver --> Vehicle : drives
```

Common multiplicities:

- `1` — exactly one
- `0..1` — zero or one
- `0..*` or `*` — zero or many
- `1..*` — one or many
- `m..n` — between m and n

## Generic classes

Use `~T~` for generic type parameters; instantiate with a concrete type in the same tilde form:

```mermaid
classDiagram
    class List~T~ {
        +add(item: T)
        +get(index: int) T
    }
    List~String~ <-- StringProcessor
```

## Stereotypes and abstract classes

Mark special class types with `<<stereotype>>` inside the class block:

- `<<interface>>` — pair with `<|..` realization links
- `<<abstract>>` — abstract class; mark abstract members with a trailing `*`
- `<<service>>` — service-layer class
- `<<dataclass>>` — data-transfer or data-carrier class
- `<<enumeration>>` — enum; list the values as bare members

```mermaid
classDiagram
    class IRepository {
        <<interface>>
        +save(entity)
        +findById(id)
    }
    class UserService {
        <<service>>
        +createUser()
    }
    class UserDTO {
        <<dataclass>>
        +String name
        +String email
    }
    class Shape {
        <<abstract>>
        +int x
        +int y
        +draw()*
        +move(x, y)
    }
    class OrderStatus {
        <<enumeration>>
        PENDING
        PAID
        SHIPPED
        DELIVERED
        CANCELLED
    }
    Shape <|-- Circle
    Shape <|-- Rectangle
    Order --> OrderStatus
```

## Notes

Attach a note to one class with `note for <Class> "<text>"`:

```mermaid
classDiagram
    class Order {
        +Decimal total
    }
    note for Order "Total must equal the sum of line item subtotals."
```

## Domain-driven design stereotypes

- `<<entity>>` — object with a stable identity
- `<<value object>>` — immutable object compared by value
- `<<aggregate root>>` — entry point of an aggregate; composition-links its members

```mermaid
classDiagram
    class User {
        <<entity>>
        -UUID id
        +String email
        +String name
    }
    class Money {
        <<value object>>
        +Decimal amount
        +String currency
        +add(other: Money) Money
    }
    class Address {
        <<value object>>
        +String street
        +String city
        +String postalCode
    }
    class Order {
        <<aggregate root>>
        -UUID id
        +addLineItem(item)
        +removeLineItem(item)
    }
    Order *-- LineItem
```

## Combined example

```mermaid
classDiagram
    class Customer {
        +UUID id
        +String email
        +Address shippingAddress
        +placeOrder(cart: Cart) Order
    }
    class Order {
        +UUID id
        +DateTime orderDate
        +OrderStatus status
        +calculateTotal() Decimal
    }
    class LineItem {
        +int quantity
        +Decimal pricePerUnit
        +getSubtotal() Decimal
    }
    class Product {
        +UUID id
        +String name
        +Decimal price
        +reduceStock(quantity: int)
        +isAvailable() bool
    }
    class Cart {
        +addItem(product: Product, quantity: int)
        +removeItem(product: Product)
        +getTotal() Decimal
    }
    class OrderStatus {
        <<enumeration>>
        PENDING
        PAID
        SHIPPED
    }
    Customer "1" --> "0..*" Order : places
    Customer "1" --> "1" Cart : has
    Order "1" *-- "1..*" LineItem : contains
    LineItem "1" --> "1" Product : references
    Cart "1" o-- "0..*" Product : contains
    Order --> OrderStatus
```

## Authoring tips

1. Start with core entities; add attributes and methods incrementally.
2. Show only relevant details; omit obvious getters and setters.
3. Choose between association, aggregation, and composition deliberately — they encode different ownership semantics.
4. Add multiplicity to clarify how many instances participate in each relationship.
5. Group related classes with notes or visual proximity.
6. Document invariants and business rules with notes.

## Common patterns

Repository:

```mermaid
classDiagram
    class IRepository~T~ {
        <<interface>>
        +save(entity: T)
        +findById(id: UUID) T
        +delete(entity: T)
    }
    class UserRepository {
        +findByEmail(email: String) User
    }
    IRepository~User~ <|.. UserRepository
```

Factory:

```mermaid
classDiagram
    class ShapeFactory {
        +createShape(type: String) Shape
    }
    class Shape {
        <<abstract>>
        +draw()*
    }
    ShapeFactory ..> Shape : creates
    Shape <|-- Circle
    Shape <|-- Rectangle
```

Strategy:

```mermaid
classDiagram
    class PaymentProcessor {
        -PaymentStrategy strategy
        +setStrategy(strategy: PaymentStrategy)
        +processPayment(amount: Decimal)
    }
    class PaymentStrategy {
        <<interface>>
        +pay(amount: Decimal)*
    }
    PaymentStrategy <|.. CreditCardPayment
    PaymentStrategy <|.. PayPalPayment
    PaymentProcessor --> PaymentStrategy
```
