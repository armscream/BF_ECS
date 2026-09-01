# BF_ECS — Entity Component System Architecture

**Project:** Bifrost Engine
**Module:** `BF_ECS`
**Status:** Architectural / Iterative Design
**Language:** Odin

---

# 1. Overview

`BF_ECS` is Bifrost Engine's Entity Component System.

It is inspired by [Flecs](https://flecs.dev/) and adopts many of its useful concepts around relationships, inheritance, archetypes, and data-oriented hierarchies, while being designed specifically around Bifrost's requirements:

* Large 3D game worlds
* First-person shooter workloads
* World streaming
* Network replication
* Runtime asset streaming
* Highly parallel system execution
* SIMD-friendly iteration
* Static, compile-time-known component schemas
* Dynamic runtime entity populations
* Integration with the Bifrost DAG scheduler
* Integration with Box3D
* 2D and 3D world partitioning

The ECS should provide **data ownership, queries, relationships, partition membership, and dependency information**.

The DAG remains responsible for **execution ordering and scheduling**.

Physics, rendering, networking, and other specialized systems may maintain their own specialized acceleration structures.

---

# 2. Core Philosophy

BF_ECS follows several foundational principles.

## 2.1 Compile-time-known component schemas are primary data domains

The programmer should be able to define component schemas and static archetype layouts at compile time.

For example:

```odin
Character_Archetype :: archetype(
    Transform,
    Velocity,
    Character,
    Animation_State,
)
```

The ECS therefore knows the structure of important data domains before runtime.

This allows the engine to optimize:

* component layout
* alignment
* SIMD processing
* AoSoA organization
* query matching
* archetype iteration
* cache behavior

Runtime entity populations remain dynamic.

---

# 3. Hybrid Storage Model

BF_ECS uses two primary component storage mechanisms.

```text
                 BF_ECS Storage
                      │
              ┌───────┴───────┐
              │               │
         Archetypes       Sparse Sets
              │               │
         Dense/static      Dynamic/optional
          components         components
```

## 3.1 Archetypes

Archetypes contain components that benefit from dense, contiguous storage.

Entities sharing the same primary component schema belong to the same archetype domain.

Archetypes should be optimized for:

* iteration
* SIMD
* cache locality
* batch processing
* predictable layouts

Runtime population is still dynamic:

```text
Archetype: Character

Entity population:
    E1
    E2
    E3
    ...
```

Entities may be spawned and destroyed freely.

---

# 4. Sparse Components

Components that are genuinely dynamic, optional, or frequently added/removed can use sparse-set storage.

Examples might include:

* temporary gameplay state
* optional debug data
* transient effects
* editor state
* rarely-used components
* dynamic feature state

The purpose is to avoid expensive structural migration when a component is added or removed frequently.

For example:

```text
Character Archetype
    Transform
    Velocity
    Character

Sparse Components
    ├── Stunned
    ├── Burning
    ├── Debug_Selected
    └── Temporary_Target
```

This is not intended to make every component sparse.

The ECS should choose storage based on workload characteristics.

---

# 5. Structural Changes

The major tradeoff of dense archetype storage is that structural changes can require movement of entity data.

BF_ECS should therefore distinguish between:

### Stable data

Data that is normally present and frequently iterated.

→ Archetype storage.

### Dynamic data

Data that is frequently attached/detached or genuinely optional.

→ Sparse-set storage.

This avoids forcing all runtime component changes through archetype migration.

The implementation may later incorporate cached structural transitions where beneficial.

---

# 6. Relationships Are First-Class ECS Data

Relationships are not an external hierarchy subsystem.

BF_ECS treats relationships as ECS data.

Important relationships include:

```text
IsA
ChildOf
```

and potentially additional engine-specific relationships later.

Relationships can participate in:

* queries
* inheritance
* hierarchy propagation
* asset composition
* prefab composition
* editor operations
* dependency calculation
* DAG metadata

---

# 7. `IsA` / Inheritance

BF_ECS supports an inheritance model inspired by Flecs.

Conceptually:

```text
Base_Character
      ▲
      │ IsA
      │
Player_Character
      │
      └── runtime state
```

Inheritance provides an OOP-like cognitive model while retaining data-oriented execution.

This is particularly useful for:

* prefabs
* assets
* templates
* archetypal gameplay objects
* inherited configuration
* editor workflows

## 7.1 `IsA` is primarily fragmenting

`IsA` / asset inheritance should generally be treated as a **fragmenting relationship**.

This is intentional.

Asset and prefab grouping can improve downstream processing by keeping related inherited data organized.

The inheritance model should therefore not automatically force all inherited objects into one non-fragmented hierarchy.

---

# 8. `ChildOf` / Scene Hierarchy

`ChildOf` represents scene/world hierarchy.

Example:

```text
Player
 ├── Weapon
 │    ├── Magazine
 │    └── Muzzle
 └── Character_Camera
```

`ChildOf` supports both:

* fragmenting storage
* non-fragmenting storage

The storage strategy is selected according to workload.

---

# 9. Fragmenting vs Non-Fragmenting Hierarchies

BF_ECS should support two broad hierarchy strategies.

## 9.1 Fragmenting hierarchy

Children associated with different parents may be represented through separate storage fragments.

This is useful when queries frequently operate relative to a particular parent.

For example:

```text
Parent A
 ├── Child
 ├── Child
 └── Child

Parent B
 ├── Child
 └── Child
```

Parent-centric processing can benefit from this organization.

---

## 9.2 Non-fragmenting hierarchy

Large scene populations may instead remain grouped into larger storage populations.

This avoids producing thousands of tiny archetypes.

This is the preferred strategy for highly replicated scene trees where fragmentation would cause excessive archetype proliferation.

---

# 10. Default Hierarchy Strategy

For highly replicated scene trees:

> **Non-fragmenting hierarchy is the default.**

The goal is to avoid:

```text
10,000 parents
      ↓
10,000 tiny archetype populations
```

when those fragments provide little processing benefit.

Fragmenting storage remains available where it improves:

* parent-centric queries
* propagation
* hierarchy traversal
* locality
* downstream processing

---

# 11. Queries Hide Storage Strategy

User code should not need to know whether a relationship is represented through:

* fragmented storage
* non-fragmented storage
* archetype data
* sparse data
* cached relationship information

The query system abstracts the storage implementation.

For example:

```text
Query:
    Transform
    ChildOf Parent
```

should have consistent semantics regardless of how `ChildOf` is physically stored.

---

# 12. Query Caching

Queries should cache expensive structural information.

A query may cache:

* matching archetypes
* matching sparse components
* relationship information
* inherited components
* hierarchy metadata
* component offsets
* storage access information
* partition/index information where appropriate

The goal is to resolve structural information once and make repeated execution cheap.

For example:

```text
Query construction
        ↓
Resolve archetypes
        ↓
Resolve relationships
        ↓
Resolve inheritance
        ↓
Cache result
        ↓
Repeated iteration
```

---

# 13. World Partitioning

World partitioning is a first-class engine concern.

It is distinct from ECS component storage.

The world is divided into **chunks**, and each chunk is subdivided into spatial cells.

```text
World
 │
 ├── Chunk
 │    ├── Cell
 │    ├── Cell
 │    └── ...
 │
 ├── Chunk
 │    └── ...
 │
 └── ...
```

The purpose of world partitioning is not merely spatial acceleration.

Chunks are also boundaries for:

* world streaming
* asset streaming
* replication
* persistence
* residency
* activation
* spatial relevance

---

# 14. Chunk Dimensions

Chunk dimensions are defined in terms of **cells per axis**, not world-space meters.

Configuration is determined by project settings.

Conceptually:

```odin
chunk_size: u32
cell_size:  f32
```

For example:

```text
chunk_size = 16
cell_size  = 4m
```

produces:

```text
16 × 4m = 64m chunk width
```

In 3D:

```text
16 × 16 × 16 cells
= 4096 cells per chunk
```

In 2D:

```text
16 × 16 cells
= 256 cells per chunk
```

The project configuration determines whether the world partition is:

```text
2D
```

or:

```text
3D
```

This allows the same ECS partitioning model to support both.

---

# 15. Why Chunk Size Is Cell Count

Defining chunks as a number of cells rather than an independent world-space size guarantees that:

```text
chunk_size × cell_size
```

always produces an exact partition boundary.

This gives a clean mapping:

```text
World Position
      ↓
Chunk Coordinate
      ↓
Local Position
      ↓
Cell Coordinate
      ↓
Cell Index
```

There is no need for cell-coordinate wrapping or ambiguous boundary calculations.

---

# 16. Chunk Coordinate

A chunk has a logical coordinate:

```odin
Chunk_Coord :: struct {
    x: i32,
    y: i32,
    z: i32,
}
```

The actual dimensionality depends on project settings.

A 2D world may effectively use:

```text
x
y
```

while a 3D world uses:

```text
x
y
z
```

The internal representation may remain uniform where that simplifies implementation.

---

# 17. `Chunk_ID` vs `Chunk_Coord`

These should be separate concepts.

`Chunk_Coord` answers:

> Where is the chunk?

`Chunk_ID` answers:

> Which chunk is this in the partition manager?

Conceptually:

```odin
Chunk_ID :: distinct u32
```

and:

```odin
Chunk :: struct {
    id:    Chunk_ID,
    coord: Chunk_Coord,
    ...
}
```

This allows chunk identity to remain stable even if coordinate lookup or chunk storage changes.

---

# 18. Entity Chunk Membership

Entities should have a current world-partition membership.

Conceptually:

```text
Entity
   ↓
Chunk_ID
```

This can initially be maintained through a dense entity-indexed array:

```odin
entity_chunk: []Chunk_ID
```

allocated according to the maximum entity capacity.

This allows the ECS to quickly determine whether an entity crossed a chunk boundary.

---

# 19. Chunk Membership Is Not Component Storage

`Chunk_ID` represents spatial/world membership.

It should not cause component data to leave the normal ECS storage mechanisms.

The initial architecture is:

```text
Entity
   │
   ├── Archetype/Sparse components
   │
   └── Chunk_ID
```

The chunk system maintains an index:

```text
Chunk_ID
    ↓
Entity IDs
```

The actual component data remains owned by:

```text
Archetypes
Sparse Sets
```

This keeps world partitioning independent from physical component storage.

---

# 20. Future Chunk-Resident Storage

The architecture should not prevent future optimization where archetype populations are physically partitioned by world chunk.

For example, an archetype could eventually be organized internally as:

```text
Character Archetype
    │
    ├── Chunk 42
    ├── Chunk 43
    └── Chunk 44
```

This is an implementation optimization.

The public ECS model should continue to present:

```text
Character + Transform
```

rather than exposing chunk-specific storage.

This preserves freedom to optimize later.

---

# 21. Chunk Residency

A chunk can exist independently of whether its entity data is currently resident.

For example:

```text
Chunk 42
    exists = true
    loaded = true
    active = true
```

or:

```text
Chunk 43
    exists = true
    loaded = false
    active = false
```

An unloaded chunk may still have:

* terrain data
* asset references
* persistent entity records
* streaming metadata
* procedural generation state
* replication metadata

Therefore:

> **An empty resident entity population does not necessarily mean the chunk itself should be destroyed.**

---

# 22. Spatial Index

Each loaded/active chunk can maintain a fine-grained spatial index.

The spatial index answers:

> Which entities are spatially close to this position or region?

The initial implementation is a uniform cell grid.

Conceptually:

```text
Chunk
 │
 └── Spatial Index
       │
       ├── Cell 0
       ├── Cell 1
       ├── Cell 2
       └── ...
```

---

# 23. Local Spatial Grid

Because the chunk dimensions are explicitly defined as a number of cells, a local chunk grid does not need to use hashing for its normal cell addressing.

For example:

```text
chunk_size = 16
```

gives:

```text
16 × 16 × 16
```

cells in 3D.

A cell coordinate:

```text
(x, y, z)
```

can be converted directly into a linear cell index.

Conceptually:

```text
cell_index =
    x +
    y * cells_per_axis +
    z * cells_per_axis * cells_per_axis
```

This avoids:

* hash computation
* hash collisions
* hash table probing
* per-cell tree nodes

The spatial structure becomes a compact flat grid.

---

# 24. Packed Cell Entity Storage

Cells should not initially use a dynamically allocated entity list for every cell.

A more cache-friendly representation is:

```text
Cell counts
     ↓
Prefix sum / offsets
     ↓
Packed entity IDs
```

Example:

```text
Cell 0 → E1 E2 E3
Cell 1 → empty
Cell 2 → E7
Cell 3 → E4 E5
```

can become:

```text
counts:
3 0 1 2

offsets:
0 3 3 4

entities:
E1 E2 E3 E7 E4 E5
```

This is highly suitable for read-heavy spatial queries.

---

# 25. Why Packed Spatial Storage

The spatial index is expected to be:

* queried frequently
* read much more often than written
* rebuilt in batches
* traversed sequentially within candidate cells

Packed entity IDs provide:

* compact memory
* fewer allocations
* predictable iteration
* good cache locality
* efficient parallel construction
* efficient read-only queries

---

# 26. Spatial Index Is Not ECS Storage

The spatial index contains:

```text
Entity IDs
```

not:

```text
Transform
Velocity
Health
...
```

The spatial index is therefore a candidate generator.

For example:

```text
Spatial Query
    ↓
Candidate Entity IDs
    ↓
ECS filtering
    ↓
Component access
```

This keeps the spatial system independent from component layout.

---

# 27. Spatial Queries

BF_ECS should eventually support spatial query forms such as:

```text
Radius
AABB
Sphere
Cell
Chunk
```

and potentially additional primitives.

A radius query follows approximately:

```text
World position
      ↓
Overlapping chunks
      ↓
Overlapping cells
      ↓
Candidate entities
      ↓
Exact spatial test
      ↓
ECS filtering
```

The spatial grid is therefore a broad-phase candidate generator.

---

# 28. Chunk Query vs Spatial Query

These are distinct operations.

### Chunk query

```text
"Give me entities belonging to Chunk 42."
```

This does not require geometric calculations.

### Spatial query

```text
"Give me entities within 10 meters of this point."
```

This may involve:

```text
chunks
    ↓
cells
    ↓
candidate entities
    ↓
distance test
```

This distinction is important for replication and streaming.

---

# 29. Spatial Index Selection

The initial spatial index will use a uniform grid.

However, the BF_ECS architecture should not require that every spatial workload use the same structure.

Possible future implementations include:

```text
Uniform Grid
Spatial Hash
BVH
Other specialized indexes
```

The ECS should depend on the semantic concept:

```text
Spatial_Index
```

rather than hard-coding all future behavior around one algorithm.

---

# 30. World Partition vs Specialized Spatial Structures

World partitioning should not replace specialized spatial structures.

Different engine systems have different spatial workloads.

```text
World Partition
    → streaming / replication / residency

BF_ECS Spatial Index
    → gameplay spatial queries

Box3D Broad Phase
    → physics collision queries

Renderer Culling Structures
    → visibility
```

A single structure should not be forced to solve all of these problems.

---

# 31. Physics

BF_ECS should not own the physics broad phase.

Box3D can maintain the spatial acceleration structures appropriate for collision detection.

For example:

```text
BF_ECS
    │
    └── Transform / Bounds
             │
             ▼
           Box3D
             │
             └── Physics broad phase
```

Ray casts and shape casts against physics objects should use the physics API rather than the ECS spatial index.

---

# 32. Rendering

Rendering has different spatial requirements.

The renderer may maintain:

* visibility structures
* frustum culling
* hierarchical bounds
* GPU culling data
* occlusion data
* draw extraction structures

The BF_ECS spatial index should not attempt to replace renderer-specific culling.

The ECS supplies entity/component data and relevant spatial information.

---

# 33. Chunk Streaming

Chunks form natural streaming boundaries.

Conceptually:

```text
Player position
      ↓
Required chunks
      ↓
Load / unload
      ↓
Activate / deactivate
      ↓
ECS population
```

Streaming can therefore operate on chunk IDs rather than individual entities.

---

# 34. Asset Streaming

World chunks can also define asset residency.

For example:

```text
Chunk 100
    ├── entities
    ├── terrain
    ├── meshes
    ├── textures
    └── materials
```

The ECS does not need to own the assets.

It provides the entity population and references required by the asset/streaming systems.

---

# 35. Replication

Chunk membership is particularly useful for network replication.

A replication system can ask:

```text
Which entities belong to Chunk 42?
```

and then apply ECS filtering:

```text
Chunk 42
    ↓
Entity IDs
    ↓
WITH Replicable
WITH Network_ID
...
```

This avoids scanning the entire world.

---

# 36. Replication Interest

A client's interest region can be represented as a set of chunks.

For example:

```text
        ┌───────┬───────┬───────┐
        │ C10   │ C11   │ C12   │
        ├───────┼───────┼───────┤
        │ C13   │ C14   │ C15   │
        ├───────┼───────┼───────┤
        │ C16   │ C17   │ C18   │
        └───────┴───────┴───────┘
                  ▲
                Client
```

The replication system can first select relevant chunks and then query their entities.

Fine-grained spatial filtering can subsequently use the cell index if necessary.

---

# 37. Chunk + Spatial Query Hierarchy

The intended hierarchy is:

```text
World
 │
 ▼
Chunks
 │
 ▼
Cells
 │
 ▼
Entity candidates
 │
 ▼
ECS filtering
 │
 ▼
Component access
```

This gives progressively finer filtering.

For a large world:

```text
Millions of world entities
        ↓
Resident chunks
        ↓
Relevant chunks
        ↓
Relevant cells
        ↓
Candidate entities
        ↓
Matching ECS entities
```

This is the desired scalability model.

---

# 38. Dirty Tracking

Spatial membership should be updated incrementally.

An entity stores its current chunk membership:

```text
Entity
    ↓
Current Chunk_ID
```

After movement:

```text
New position
    ↓
Calculate Chunk_ID
    ↓
Compare with old Chunk_ID
```

If unchanged:

```text
No chunk migration
```

If changed:

```text
Old chunk → dirty
New chunk → dirty
Entity membership → updated
```

---

# 39. Cell Dirty Tracking

Chunk membership and cell membership are separate.

An entity can move:

```text
Cell 4 → Cell 5
```

without changing:

```text
Chunk 42
```

Therefore the spatial index should distinguish:

```text
Chunk migration
```

from:

```text
Cell migration
```

Example:

```text
Movement
   │
   ├── same chunk
   │      └── possibly different cell
   │
   └── different chunk
          ├── old chunk dirty
          └── new chunk dirty
```

---

# 40. Dirty Spatial Rebuilds

The spatial index should favor batch updates.

Typical frame:

```text
Thousands of entities
       ↓
Only a subset move between cells
       ↓
Only affected spatial populations are rebuilt
```

This avoids rebuilding every spatial index every frame.

However, the design must also handle pathological cases:

* teleportation
* mass spawning
* network correction
* destruction events
* streaming events
* large-scale world changes

without requiring a completely different implementation.

---

# 41. Packed Rebuild Model

A dirty spatial population can be rebuilt using:

```text
1. Count entities per cell
2. Prefix-sum counts
3. Compute offsets
4. Scatter entity IDs
5. Publish the rebuilt index
```

This is attractive for SIMD and parallel processing.

It also avoids maintaining expensive per-cell linked lists.

---

# 42. Read/Write Phases

The spatial index should ideally have a clear lifecycle:

```text
Transform systems
       ↓
Partition update
       ↓
Spatial index rebuild
       ↓
Spatial queries
```

After publication, spatial queries should be read-only.

This is particularly important for DAG integration.

---

# 43. Potential Future Double Buffering

The architecture should leave room for:

```text
Spatial Index A
       │
       └── currently queried

Spatial Index B
       │
       └── being rebuilt
```

Then:

```text
Rebuild
   ↓
Publish
   ↓
Swap
```

This could allow spatial index construction to run in parallel with other work.

Double buffering is not required for the first implementation.

---

# 44. Hierarchy + Spatial Partitioning

Hierarchy propagation should feed spatial state.

Conceptually:

```text
Local Transform
      ↓
Hierarchy propagation
      ↓
World Transform
      ↓
World Bounds
      ↓
Chunk / Cell membership
      ↓
Spatial index
```

This ensures that parent movement can correctly update descendants.

---

# 45. Hierarchy Depth

Hierarchy depth should become ECS metadata.

For example:

```text
Root
  depth = 0

Child
  depth = 1

Grandchild
  depth = 2
```

This can be useful for:

* transform propagation
* hierarchy processing
* ordering
* parallelization
* dependency generation

Most importantly, hierarchy depth can feed the DAG.

---

# 46. DAG Integration

The DAG remains the engine's execution system.

BF_ECS provides:

* data access information
* component dependencies
* relationship dependencies
* hierarchy metadata
* spatial/partition dependencies
* system registration information

The ECS should not become another scheduler.

---

# 47. Example DAG Dependency

A typical frame may look like:

```text
Movement
    ↓
Transform Update
    ↓
Hierarchy Propagation
    ↓
World Bounds
    ↓
World Partition Update
    ↓
Spatial Index Rebuild
    ↓
        ┌───────────────┬───────────────┐
        ▼               ▼               ▼
       AI          Replication      Gameplay
        │
        ▼
    Rendering Extract
```

Physics may have a related but independently managed path:

```text
Transform
    ↓
Physics Synchronization
    ↓
Box3D Broad Phase
```

---

# 48. ECS Should Provide Dependency Information

A system declaring:

```text
READ:
    Transform

WRITE:
    Velocity
```

provides information that the DAG can use.

A spatial system may declare:

```text
READ:
    World Transform
    Bounds

WRITE:
    Spatial Partition
```

The DAG then determines where it executes.

This keeps execution scheduling outside BF_ECS.

---

# 49. SIMD and AoSoA

SIMD and AoSoA are storage-level optimizations.

They should not dominate the public ECS API.

The desired layering is:

```text
ECS API
    ↓
Archetype
    ↓
Storage layout
    ↓
SoA / AoSoA
    ↓
SIMD
```

User code should not need to manually manage SIMD layout merely to use the ECS.

---

# 50. Query Execution

A query should conceptually perform:

```text
Query definition
      ↓
Structural matching
      ↓
Storage matching
      ↓
Partition filtering
      ↓
Spatial filtering
      ↓
Component fetch
      ↓
Iteration
```

The exact ordering can be optimized.

The query planner should choose the cheapest available filtering path.

---

# 51. Query Candidate Sources

Potential candidate sources include:

```text
Archetype index
Sparse component index
Chunk index
Spatial index
Relationship index
Inheritance cache
```

A query may combine several.

For example:

```text
Chunk 42
WITH Character
WITH Replicable
```

could become:

```text
Chunk index
    ↓
candidate IDs
    ↓
Character filter
    ↓
Replicable filter
```

Whereas:

```text
Transform
Velocity
```

may simply iterate matching dense archetypes.

---

# 52. Query Planner Principle

The ECS should not assume that the most sophisticated index is always fastest.

For small populations:

```text
Dense ECS iteration
```

may beat:

```text
Spatial index lookup
```

because dense iteration has excellent cache locality.

Therefore spatial indexing is an optimization for workloads where reducing candidate population outweighs its maintenance and lookup costs.

---

# 53. Large FPS Workload

BF_ECS is particularly intended for workloads such as:

```text
Thousands of entities
Hundreds/thousands of AI agents
Large streamed worlds
Frequent replication queries
Frequent proximity queries
Many moving entities
Large static environments
```

The architecture therefore emphasizes:

* coarse chunk filtering
* fine spatial filtering
* dense ECS iteration
* incremental spatial maintenance
* batch rebuilding
* DAG scheduling
* subsystem-specific spatial structures

---

# 54. What BF_ECS Does Not Own

BF_ECS should not become responsible for every engine subsystem.

It should not directly own:

```text
Physics broad phase
Renderer visibility structures
GPU culling
Network transport
Asset database
Streaming implementation
```

Instead, it exposes the data and indexing mechanisms those systems need.

---

# 55. Architectural Separation

The intended separation is:

```text
                         BIFROST
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
          ▼                 ▼                 ▼
       BF_ECS             Box3D            Renderer
          │                 │                 │
          │                 │                 │
    ┌─────┴─────┐      Physics BP       Visibility
    │           │
    ▼           ▼
 Storage     Partition
    │           │
 ┌──┴───┐    ┌──┴────────┐
 │      │    │           │
Arch  Sparse Chunk     Spatial
             │          Index
             │
             ▼
          World Data
```

---

# 56. World Partition Responsibilities

The world partition system is responsible for:

* chunk coordinate calculation
* chunk identity
* chunk membership
* cell calculation
* spatial candidate indexing
* dirty tracking
* resident population indexing
* chunk-level spatial queries

It may also expose information needed by:

* streaming
* replication
* persistence
* AI
* gameplay

but should not own those systems.

---

# 57. Streaming Responsibilities

The streaming subsystem is responsible for:

* deciding which chunks should be resident
* loading chunk data
* unloading chunk data
* asset residency
* asynchronous IO
* serialization/deserialization

It consumes world-partition information from BF_ECS.

---

# 58. Replication Responsibilities

NetCode is responsible for:

* client interest
* replication policy
* network IDs
* serialization
* bandwidth management
* reliable/unreliable delivery

BF_ECS supplies efficient access to:

```text
Chunk → Entity population
```

and spatial candidate populations.

---

# 59. Persistence

The chunk boundary should also be usable by persistence.

A chunk can be serialized independently:

```text
Chunk
    ↓
Entity population
    ↓
Archetype data
    ↓
Sparse component data
    ↓
Relationship data
    ↓
Asset references
```

This is one of the reasons world chunks are more than merely spatial acceleration structures.

---

# 60. Asset / Prefab / Scene Unification

Asset inheritance and scene hierarchy should be conceptually unified.

The editor should be able to represent:

```text
Asset
    ↓
Prefab
    ↓
Instance
    ↓
Scene hierarchy
```

using the same conceptual ECS relationship model.

`IsA` provides inheritance.

`ChildOf` provides hierarchy.

This gives the editor one coherent model rather than separate object and asset systems.

---

# 61. Design Principle

A useful philosophical statement for BF_ECS is:

> **Flecs asks "what storage strategy makes this relationship fastest?"**

BF_ECS extends this idea:

> **What storage and indexing strategy makes this component or relationship fastest for the workload being performed?**

Components may use:

```text
Archetype
Sparse Set
```

Relationships may use:

```text
Fragmented
Non-fragmented
Cached
```

World queries may use:

```text
Chunk
Cell
Spatial Index
```

Specialized subsystems may use:

```text
BVH
SAP
GPU structures
```

The API should hide those implementation choices wherever practical.

---

# 62. Target Data Flow

The desired high-level data flow is:

```text
                         ENTITY
                           │
             ┌─────────────┼─────────────┐
             │             │             │
             ▼             ▼             ▼
         Archetype     Sparse Set     Chunk_ID
             │             │             │
             │             │             ▼
             │             │        Chunk Registry
             │             │             │
             │             │             ▼
             │             │       Spatial Index
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                         QUERY
                           │
                    Candidate filtering
                           │
                           ▼
                     ECS iteration
                           │
                           ▼
                          DAG
```

---

# 63. Initial Implementation Strategy

BF_ECS should be developed incrementally.

## Phase 1 — Pure Sparse Set

Implement:

* Entity IDs
* generations
* sparse-set component storage
* basic queries
* entity lifecycle

Focus on correctness and API design.

---

## Phase 2 — Static Archetypes

Add:

* compile-time component schemas
* archetype storage
* dense iteration
* archetype matching
* runtime populations

---

## Phase 3 — Relationships

Add:

* `IsA`
* `ChildOf`
* relationship queries
* hierarchy metadata
* inheritance resolution

---

## Phase 4 — World Partition

Add:

* `Chunk_ID`
* `Chunk_Coord`
* chunk registry
* entity chunk membership
* chunk queries

---

## Phase 5 — Spatial Index

Add:

* cell coordinate calculation
* local chunk grid
* packed entity populations
* radius queries
* AABB queries
* incremental dirty tracking

---

## Phase 6 — Streaming / Replication Integration

Connect:

```text
Chunk
    ↓
Streaming
Replication
Persistence
```

without making those systems part of BF_ECS.

---

## Phase 7 — DAG Integration

Expose:

* ECS access dependencies
* hierarchy dependencies
* partition dependencies
* spatial update dependencies
* system registration

to the DAG.

---

## Phase 8 — Optimization

Profile and optimize:

* archetype layout
* AoSoA
* SIMD
* query caches
* spatial rebuilds
* chunk indexing
* parallel rebuilds
* cache behavior

Only introduce more complicated structures when profiling demonstrates their value.

---

# 64. Important Non-Goals

BF_ECS should initially avoid:

* universal spatial structures
* mandatory BVHs
* mandatory octrees
* mandatory spatial hashing
* ECS-owned physics broad phases
* ECS-owned rendering culling
* forcing all components into archetypes
* forcing all components into sparse sets
* exposing storage implementation details to users
* prematurely optimizing every query type

The architecture should remain extensible.

---

# 65. Current Proposed Core Types

A conceptual starting point is:

```odin
Entity :: struct {
    id:         u32,
    generation: u32,
}
```

Partition membership:

```odin
Chunk_ID :: distinct u32

Chunk_Coord :: struct {
    x: i32,
    y: i32,
    z: i32,
}
```

Chunk:

```odin
Chunk :: struct {
    id:       Chunk_ID,
    coord:    Chunk_Coord,

    spatial:  Spatial_Index,

    // Residency/streaming state will evolve separately.
}
```

World partition:

```odin
World_Spatial :: struct {
    chunk_size: u32, // cells per chunk axis
    cell_size:  f32, // world-space cell size in meters

    chunks: ...,
}
```

Per-entity membership:

```odin
entity_chunk: []Chunk_ID
```

The final API and ownership model are intentionally not yet frozen.

---

# 66. Project Configuration

World dimensionality and partition dimensions should come from project settings.

Conceptually:

```text
Project Settings
    │
    ├── world dimension: 2D / 3D
    │
    ├── cell size: meters
    │
    └── chunk size: cells per axis
```

Example 3D configuration:

```text
dimension  = 3D
cell_size  = 4m
chunk_size = 16 cells
```

Result:

```text
Chunk:
64m × 64m × 64m

Cells:
16 × 16 × 16

Total:
4096 cells/chunk
```

Example 2D configuration:

```text
dimension  = 2D
cell_size  = 4m
chunk_size = 16 cells
```

Result:

```text
Chunk:
64m × 64m

Cells:
16 × 16

Total:
256 cells/chunk
```

This allows one partition architecture to serve both types of project.

---

# 67. Guiding Principle

The most important architectural rule is:

> **World partitioning is fundamental; spatial acceleration is replaceable.**

Chunks define coarse world organization and are useful for:

* residency
* streaming
* replication
* persistence
* activation
* spatial relevance

Cells provide fine-grained spatial candidate selection.

The actual spatial indexing algorithm may evolve independently.

---

# 68. Final Architecture

The current intended BF_ECS architecture is:

```text
                           BF_ECS
                              │
       ┌──────────────────────┼──────────────────────┐
       │                      │                      │
       ▼                      ▼                      ▼
 COMPONENT STORAGE       RELATIONSHIPS        WORLD PARTITION
       │                      │                      │
 ┌─────┴─────┐          IsA / ChildOf          Chunk_ID
 │           │                                     │
 ▼           ▼                                     ▼
Archetypes Sparse Sets                      Chunk Registry
                                                │
                                                ▼
                                           Local Cell Grid
                                                │
                                                ▼
                                          Spatial Candidates
       │                      │                      │
       └──────────────────────┼──────────────────────┘
                              ▼
                           QUERIES
                              │
                 ┌────────────┼────────────┐
                 ▼            ▼            ▼
             Component      Chunk       Spatial
              matching     matching     matching
                 │            │            │
                 └────────────┼────────────┘
                              ▼
                         ECS iteration
                              │
                              ▼
                             DAG
```

With specialized subsystems remaining independent:

```text
             BF_ECS
                │
     ┌──────────┼───────────┐
     ▼          ▼           ▼
  NetCode     Box3D      Renderer
     │          │           │
 Chunk/      Physics      Visibility
 Spatial     Broadphase   Structures
 Queries     / BVH/etc.   / Culling
```

The result is a hybrid ECS that combines:

* compile-time-known static schemas
* dense archetype storage
* sparse runtime components
* first-class relationships
* Flecs-inspired inheritance
* flexible hierarchy fragmentation
* world chunking
* local spatial indexing
* streaming-aware populations
* replication-aware populations
* cached queries
* SIMD/AoSoA-friendly storage
* and DAG-driven execution

without making any one subsystem responsible for every kind of data organization or spatial problem.

---

# 69. Architectural Summary

BF_ECS should ultimately answer four different questions efficiently:

### 1. What data does this entity have?

```text
Archetype / Sparse Set
```

### 2. What entities are structurally related?

```text
Relationships / Inheritance
```

### 3. What world region contains this entity?

```text
Chunk_ID / World Partition
```

### 4. What entities are spatially relevant?

```text
Chunk → Cell → Spatial Index
```

The ECS then combines those answers into efficient queries, while the DAG determines **when those queries and updates execute**.

This separation is the foundation of the BF_ECS architecture.
