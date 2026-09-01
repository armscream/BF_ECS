<BF_ECS>

An entity component system for Odin, inspired by FLECS.

**Description**
Hybrid ECS with static compile-time archetypes, and an otherwise sparse-set for runtime dynamic component changes. 
Hybrid means that the archetypes are statically allocated, and the runtime component changes are stored in a sparse-set.
It is also a hybrid in the sense that we can switch between fragmenting and non-fragmenting hierarchies as Sander Martens discussed in his Medium article: [Building an ECS: Data Oriented Hierarchies](https://ajmmertens.medium.com/building-an-ecs-data-oriented-hierarchies-62fb2847d100).

This will be itterated upon slowly, starting from a pure sparse-set implementation, and then adding more features.
The key is that it will be coupled with the DAG, hopefully not too badly, but this will allow for a very performant and well
tailored system.

The Inheretence system outlined by Sander as implemented in FLECS allows for OOP-minded individuals, and anyone else to adapt 
to ECS much easier, as it has that same cognitive benefit that the OOP paradym brings, but while hopefully not thrashing the cache.

Static compile-time archetypes means that the programmer would declare the static archetypes, but we will avoid any expensive
component changes in runtime having those belong to a sparse-set. Theoretically, but this may change based on how it interacts with the inheritence system, there may be a reason that this is not normally done in ECS's.


Author: <Armscream>

**Usage**
This entity component system is designed to be used with the Bifrost engine and should not be used outside of it.

**License**
This Repository inherits the licensing of the Bifrost engine.
