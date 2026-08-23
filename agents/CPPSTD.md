# AI Agent or Harness Guidance: C++ Project Layout and Coding Standards

This file provides context, rules, and commands for AI agents or harnesses operating on this repository. Follow these constraints strictly for all generation, refactoring, and bug-fixing tasks.

## C++ Coding Standards & Style Preferences

### 1. Modern Language Standards
* **Target Dialect:** Force compliance with **C++23** or higher.
* **Keywords:** Use `auto` for complex type deductions, lambdas, and iterators. Do not overuse it for primitive types where it hurts readability.
* **Type Safety:** Prefer strongly typed `enum class` over traditional C-style `enum`.
* **Constants:** Use `constexpr` for all compile-time constants and expressions instead of `#define`. Reserve `consteval` for immediate functions that must only ever execute at compile time — it does not apply to plain constants.
* **Compile-Time Branching:** Prefer `if consteval { ... } else { ... }` over `std::is_constant_evaluated()` to branch on whether code is running in a constant-evaluated context.

### 2. Memory Management & Ownership
* **RAII:** Adhere strictly to Resource Acquisition Is Initialization (RAII) patterns.
* **Raw Pointers:** Never use `new` or `delete`. Raw pointers (`T*`) are acceptable strictly as non-owning, re-bindable observers.
* **Smart Pointers:** Use `std::unique_ptr` by default for exclusive ownership. Use `std::shared_ptr` and `std::weak_ptr` only when shared ownership lifecycle is explicitly required.
* **Initialization:** Always create smart pointers using `std::make_unique<T>()` or `std::make_shared<T>()`.
* **Null Pointer:** Use `nullptr` exclusively. Never use `NULL` or `0` for pointers.

### 3. Naming & Formatting Conventions
* **Files:** Use `.cpp` for source implementations and `.h` or `.hpp` for headers.
* **Header Guards:** Protect all header files with `#pragma once`. Do not use macro-based `#ifndef` guards.
* **Classes & Structs:** PascalCase (e.g., `class NetworkManager;`).
* **Functions & Methods:** camelCase (e.g., `void initializeSocket();`).
* **Variables & Arguments:** snake_case (e.g., `int retry_count;`).
* **Private Members:** Prefix with an underscore or use a `m_` prefix (e.g., `_connection_pool` or `m_connection_pool`). Keep this consistent across the codebase.
* **Namespaces:** Wrap all project code inside a dedicated namespace (e.g., `namespace ProjectName { ... }`). Never use `using namespace std;` in header files.

### 4. Robust Error Handling
* **Exceptions:** Prefer throwing standard exceptions (`std::runtime_error`, `std::invalid_argument`) for exceptional runtime errors.
* **Guarantees:** Ensure functions provide at least the basic exception guarantee. Mark non-throwing functions explicitly with `noexcept`.
* **Alternative Patterns:** For performance-critical or non-exception code paths, use standard alternatives like `std::optional<T>` or `std::expected<T, E>` to return expected failures without throwing.

### 5. Architectural Paradigms
* **Composition over Inheritance:** Favor loose coupling and object composition over deep inheritance hierarchies.
* **Virtual Destructors:** Ensure any class with a virtual function explicitly defines a `virtual ~ClassName() = default;`.
* **Explicit Overrides:** Always tag derived class overrides with the `override` keyword. Do not repeat `virtual`.
* **Performance:** Pass complex objects by const reference (`const T&`) to eliminate unnecessary copies. Pass primitives and cheap-to-copy types (e.g., `std::string_view`, `std::span`) by value.
* **Explicit Object Parameter:** Prefer C++23's deducing `this` (e.g. `auto method(this Self&& self)`) over CRTP for static polymorphism, and to unify const/non-const or lvalue/rvalue overloads into a single templated body.

### 6. Formatted Output
* **Printing:** Prefer `std::print` / `std::println` (`<print>`) over `printf` or `std::cout` chains for simple formatted output.
* **Formatting:** Build formatted strings with `std::format` / `std::vformat` instead of manual concatenation or stream manipulators.
