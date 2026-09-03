// Engine/src/Modules/BF_ECS/World.odin
package BF_ECS

import ode "/ode_ecs/src"
import "base:runtime"

//* WORLD SETTINGS
World_Settings :: struct {
	// maximum # of simultaneously alive entities.
	entities_capacity:        u32,
	// # of component tables expected in the main gameplay DB.
	gameplay_tables_capacity: int,
	// # of preallocated views.
	gameplay_views_capacity:  int,
	// # of cmd buffers
	command_buffers_capacity: int,
}
// Sensible first default.
// This is intentionally a capacity rather than a hard req't on the # of entities that will exist.
WORLD_DEFAULT_SETTINGS :: World_Settings {
	entities_capacity        = 65_536,
	gameplay_tables_capacity = 128,
	gameplay_views_capacity  = 64,
	command_buffers_capacity = 4,
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
	allocator:       runtime.Allocator,
	settings:        World_Settings,
	// Shared entity namespace
	// Every DB attached to this Overbase sees the same Entity IDs.
	// This is the foundation for cross-DB entity references btw: GameplayDB, SpatialDB, NetworkDB, EditorDB
	// All refer to the same entity IDs
	overbase:        ode.Overbase,
	entities:        Entity_Store,
	gameplay:        Database, // main gameplay DB
	registry:        Component_Registry, // Component schema
	views:           [dynamic]^View, // Persistent queries.
	command_buffers: [dynamic]^Command_Buffer, // Persistent cmd buffers.
	// frame state
	tick:            u64,
	frame_idx:       u64,
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
	component_registry_init(&world.registry, allocator, settings.gameplay_tables_capacity)
	// Gameplay DB
	// This DB shares the overbase rather than creating it's own entity namespace.
	if !database_init(
		&world.gameplay,
		&world.overbase,
		.Gameplay,
		"Gameplay",
		allocator,
		settings.gameplay_tables_capacity,
		settings.gameplay_views_capacity,
		32,
		8,
		settings.command_buffers_capacity,
		8,
	) {
		entity_store_destroy(&world.entities)
		ode.overbase_terminate(&world.overbase)
		free(world, allocator)
		return nil
	}

	return world
}

//* DESTRUCTION
world_destroy :: proc(world: ^World) {
	if world == nil do return
	// destroy persistent ECS objects
	for buffer in world.command_buffers {
		command_buffer_destroy(buffer)
		free(buffer, world.allocator)
	}
	delete(world.command_buffers)
	for view in world.views {
		view_destroy(view)
		free(view, world.allocator)
	}
	delete(world.views)
	// DB must be terminated before their shared Overbase.
	// ODE_ECS explicitly req's DB to detach before terminating the overbase.
	database_destroy(&world.gameplay)
	component_registry_destroy(&world.registry)
	entity_store_destroy(&world.entities)
	ode.overbase_terminate(&world.overbase)
	free(world, world.allocator)
}

//* FRAME
world_begin_frame :: proc(world: ^World, frame_idx: u64) {
	if world == nil do return
	world.frame_idx = frame_idx
}
world_end_frame :: proc(world: ^World) {
	if world == nil do return
	// Structural mutations should normally be performed through ODE_ECS, cmd buffers and replayed at the appropriate sync point.
	// packing can then happen here, or throguh the scheduler's ECS stage.
	// We int dont automatically pack yet. The scheduler will own that policy.
}

//* ENTITY API
world_create_entity :: proc(world: ^World) -> Entity {
	if world == nil do return ENTITY_INVALID
	return entity_create(&world.entities)
}
world_destroy_entity :: proc(world: ^World, entity: ^Entity) -> bool {
	if world == nil do return false
	return entity_destroy(&world.entities, entity^)
}
world_entity_is_alive :: proc(world: ^World, entity: Entity) -> bool {
	if world == nil do return false
	return entity_is_alive(&world.entities, entity)
}
world_entity_count :: proc(world: ^World) -> int {
	if world == nil do return 0
	return entity_count(&world.entities)
}

//* COMPONENT REGISTRATION
world_register_component :: proc(
	$T: typeid,
	world: ^World,
	name: string,
	table: ^ode.Table(T),
	flags: Component_Flags = {.Runtime},
) -> Component_ID {
	assert(world != nil)
	return component_register(T, &world.registry, name, table, flags)
}

//* View Creation
world_view_create :: proc(
	world: ^World,
	name: string,
	includes: []^ode.Shared_Table,
	excludes: []^ode.Shared_Table = nil,
	any_of: []^ode.Shared_Table = nil,
	filter: proc(row: ^ode.View_Row, user_data: rawptr) -> bool = nil,
) -> ^View {
	if world == nil do return nil
	view := new(View, world.allocator)
	if !view_init(view, &world.gameplay, name, includes, excludes, any_of, filter) {
		free(view, world.allocator)
		return nil
	}
	append(&world.views, view)
	return view
}
//* View destruction
world_view_destroy :: proc(world: ^World, view: ^View) {
	if world == nil || view == nil do return
	for i := 0; i < len(world.views); i += 1 {
		if world.views[i] == view {
			view_destroy(view)
			free(view, world.allocator)
			unordered_remove(&world.views, i)
			return
		}
	}
}

//* Command Buffer Creation
world_command_buffer_create :: proc(
	world: ^World,
	name: string,
	commands_capacity: int = 4096,
	payload_capacity: int = 256 * 1024,
) -> ^Command_Buffer {
	if world == nil do return nil
	buffer := new(Command_Buffer, world.allocator)
	if !command_buffer_init(buffer, &world.gameplay, name, commands_capacity, payload_capacity) {
		free(buffer, world.allocator)
		return nil
	}
	append(&world.command_buffers, buffer)
	return buffer
}
//* Command Buffer Destruction
world_command_buffer_destroy :: proc(world: ^World, buffer: ^Command_Buffer) {
	if world == nil || buffer == nil do return
	for i := 0; i < len(world.command_buffers); i += 1 {
		if world.command_buffers[i] == buffer {
			command_buffer_destroy(buffer)
			free(buffer, world.allocator)
			unordered_remove(&world.command_buffers, i)
			return
		}
	}
}
