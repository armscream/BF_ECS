// Engine/src/Modules/BF_ECS/World.odin
package BF_ECS

import ode "/ode_ecs/src"
import "base:runtime"

//* WORLD SETTINGS
World_Settings :: struct {
	// maximum # of simultaneously alive entities.
	entities_capacity:        u32,
	// # of component tables expected in the main gameplay DB.
	tables_capacity:          int,
	// # of preallocated views.
	views_capacity:           int,
	// # of cmd buffers
	command_buffers_capacity: int,
}
// Sensible first default.
// This is intentionally a capacity rather than a hard req't on the # of entities that will exist.
WORLD_DEFAULT_SETTINGS :: World_Settings {
	entities_capacity        = 65_536,
	tables_capacity          = 128,
	views_capacity           = 64,
	command_buffers_capacity = 32,
}

//* WORLD DATABASE
World_Database :: struct {
	// name: ei: "Gameplay", "Editor", "Spatial", "Network"
	name: string,
	// ODE_ECS db,
	ecs:  ode.Database,
}
//* WORLD
World :: struct {
	allocator: runtime.Allocator,
	settings:  World_Settings,
	// Shared entity namespace
	// Every DB attached to this Overbase sees the same Entity IDs.
	// This is the foundation for cross-DB entity references btw: GameplayDB, SpatialDB, NetworkDB, EditorDB
	// All refer to the same entity IDs
	overbase:  ode.Overbase,
	entities:  Entity_Store,
	gameplay:  World_Database, // main gameplay DB
	registry:  Component_Registry, // Component schema
	// frame state
	tick:      u64,
	frame_idx: u64,
}
//* INITIALIZATION
world_create :: proc(
	settings: World_Settings = WORLD_DEFAULT_SETTINGS,
	allocator: runtime.Allocator = context.allocator,
) -> ^World {
	world := new(World, allocator)
	world.allocator = allocator
	world.settings = settings
	// Shared entity space
	err := ode.overbase_init(
		&world.overbase,
		settings.entities_capacity,
		4, // Reserve room for multiple DB 
		allocator,
	)
	if err != nil {
		free(world, allocator)
		return nil
	}
	// Entity store
	entity_store_init(&world.entities, &world.overbase)
	// component registry
	component_registry_init(&world.components, allocator, settings.tables_capacity)
	// Gameplay DB
	// This DB shares the overbase rather than creating it's own entity namespace.
	world.gameplay.name = "Gameplay"
	err = ode.database__init_from_overbase( // or init_from_overbase
		&world.gameplay.ecs,
		&world.overbase,
		allocator,
		settings.tables_capacity,
		32,
		8,
	)
	settings.command_buffers_capacity = 8
	if err != nil {
		component_registry_destroy(&world.registry)
		entity_store_destroy(&world.entities)
		ode.overbase__terminate(&world.overbase)
		free(world, allocator)
		return nil
	}
	world.tick = 0
	world.frame_idx = 0

	return world
}

//* DESTRUCTION
world_destroy :: proc(world: ^World) {
	if world == nil do return 
	// DB must be terminated before their shared Overbase.
	// ODE_ECS explicitly req's DB to detach before terminating the overbase.
	ode.terminate(&world.gameplay.ecs)
	component_registry_destroy(&world.registry)
	entity_store_destroy(&world.entities)
	ode.overbase_terminate(&world.overbase)
	free(world, world.allocator)
}

//* FRAME
world_begin_frame :: proc(world: ^World, frame_idx: u64) {
	if world == nil do return
	world.frame_idx = frame_idx
	world.tick += 1
}
world_end_frame :: proc(world: ^World) { 
	if world == nil do return
	// Structural mutations should normally be performed through ODE_ECS, cmd buffers and replayed at the appropriate sync point.
	// packing can then happen here, or throguh the scheduler's ECS stage.
	// We int dont automatically pack yet. The scheduler will own that policy.
}

//* DATABASE ACCESS
world_gameplay_db :: proc(world: ^World) -> ^ode.Database {
	if world == nil do return nil
	return &world.gameplay.ecs
}
//* ENTITY API
world_create_entity :: proc(world: ^World) -> ^Entity {
	if world == nil do return ENTITY_INVALID
	return entity_create(&world.entities)
}
world_destroy_entity :: proc(world: ^World, entity: ^Entity) -> bool {
	if world == nil do return false
	return entity_destroy(&world.entities, entity)
}
world_entity_count :: proc(world: ^World) -> int {
	if world == nil do return 0
	return entity_count(&world.entities)
}

//* COMPONENT REGISTRATION 
world_register_component :: proc($T: typeid, world: ^World, name: string, table: ^ode.Table(T), flags: Component_Flags = {.Runtime}) -> Component_ID {
	assert(world != nil) 
	return component_register(T, &world.registry, name, table, flags)
}
