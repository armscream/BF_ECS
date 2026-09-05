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
	command_buffer_commands: int,
	command_buffer_payload: int,
}
// Sensible first default.
WORLD_DEFAULT_SETTINGS :: World_Settings {
	entities_capacity        = 65_536, // This is intentionally a max capacity.
	gameplay_tables_capacity = 128,
	gameplay_views_capacity  = 64,
	// This is only fallback for standalone BF_ECS usage. The engine should overwrite with BF_DAG worker count.
	command_buffers_capacity = 1, 
	command_buffer_commands = 1024,
	command_buffer_payload = 1024 * 64,
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
	command_buffers: []ode.Command_Buffer, // 1 cmd buffer per scheduler worker.
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
	ode.overbase_init(
		&world.overbase,
		settings.entities_capacity,
		4, // Reserve room for multiple DB 
		allocator,
	)
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
		world_destroy(world)
		free(world, allocator)
		return nil
	}
	if !world_init_command_buffers(world) {
		world_destroy(world)
		return nil
	}

	return world
}

//* DESTRUCTION
world_destroy :: proc(world: ^World) {
	if world == nil do return
	// destroy persistent ECS objects
	world_destroy_command_buffers(world)
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

//* Command Buffer Initialization
world_init_command_buffers :: proc(world: ^World) -> bool {
	if world == nil do return false
	count := world.settings.command_buffers_capacity
	if count <= 0 do return false
	world.command_buffers = make([]ode.Command_Buffer, count, world.allocator)
	for i in 0..<count {
		if err := ode.command_buffer__init(
			&world.command_buffers[i],
			&world.gameplay.ecs,
			world.settings.command_buffer_commands,
			world.settings.command_buffer_payload,
		); err != nil {
			// Terminate everything already initialized.
			for j in 0..<i {ode.command_buffer__terminate(&world.command_buffers[j])}
			delete(world.command_buffers, world.allocator)
			world.command_buffers = nil
			return false
		}
	}
	return true
}
//* Destroy command buffers.
world_destroy_command_buffers :: proc(world: ^World) {
	if world == nil do return
	for &buffer in world.command_buffers {ode.command_buffer_terminate(&buffer)}
	if len(world.command_buffers) > 0 {delete(world.command_buffers, world.allocator)}

	world.command_buffers = nil
}
//* Worker buffer access
world_command_buffer :: #force_inline proc(world: ^World, worker_id: int) -> ^ode.Command_Buffer {
	if world == nil do return nil
	if worker_id < 0 || worker_id >= len(world.command_buffers) do return nil
	return &world.command_buffers[worker_id]
}
//* Reset cmd buffers after replay
world_reset_command_buffers :: proc(world: ^World) {
	if world == nil do return
	for &buffer in world.command_buffers {ode.command_buffer__clear(&buffer)}
}