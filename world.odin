// Engine/src/Modules/BF_ECS/World.odin
package BF_ECS

import ode "/ode_ecs/src"
import "base:runtime"

//* DB SETTINGS
World_Database_Settings :: struct {
	tables_capacity:          int,
	views_capacity:           int,
	tiny_tables_capacity:     int,
	pair_tables_capacity:     int,
	command_buffers_capacity: int,
	observers_capacity:       int,
}
//* WORLD SETTINGS
World_Settings :: struct {
	// maximum # of simultaneously alive entities.
	entities_capacity:       u32,
	gameplay:                World_Database_Settings,
	spatial:                 World_Database_Settings,
	network:                 World_Database_Settings,
	editor:                  World_Database_Settings,
	// # of cmd buffers allocated up-front. The scheduler overwrites this with its worker count.
	command_buffer_payload:  int,
	command_buffer_commands: int,
	initial_view_capacity:   int,
}
// Sensible first default.
WORLD_DEFAULT_DATABASE_SETTINGS :: World_Database_Settings {
	tables_capacity          = 128,
	views_capacity           = 64,
	tiny_tables_capacity     = 32,
	pair_tables_capacity     = 16,
	command_buffers_capacity = 32,
	observers_capacity       = 16,
}
// Sensible first default.
WORLD_DEFAULT_SETTINGS :: World_Settings {
	entities_capacity       = 65_536,
	gameplay                = WORLD_DEFAULT_DATABASE_SETTINGS,
	spatial                 = WORLD_DEFAULT_DATABASE_SETTINGS,
	network                 = WORLD_DEFAULT_DATABASE_SETTINGS,
	editor                  = WORLD_DEFAULT_DATABASE_SETTINGS,
	command_buffer_commands = 1024,
	command_buffer_payload  = 1024 * 64,
	initial_view_capacity   = 64,
}

//* WORLD
World :: struct {
	allocator:       runtime.Allocator,
	settings:        World_Settings,
	// Shared entity namespace
	overbase:        ode.Overbase,
	entities:        Entity_Store,
	// ECS databases
	gameplay:        Database, // main gameplay DB
	spatial:         Database, // Needed in future
	network:         Database, // Needed in future
	editor:          Database, // Needed in future
	custom:          Database,
	// Persistent semantic views
	views:           World_Views,
	// Global schema.
	registry:        Component_Registry,
	command_buffers: []ode.Command_Buffer, // 1 cmd buffer per scheduler worker.
	// frame state
	tick:            u64,
	frame_idx:       u64,
}

World_Views :: struct {
	// Registry of every view created via world_view_create.
	all:              [dynamic]^View,
	// gameplay
	transforms:       ^View,
	render_models:    ^View,
	// spatial
	chunk_membership: ^View,
	spatial_bounds:   ^View,
	// network
	replication:      ^View,
}

//* INITIALIZATION
world_create :: proc(
	settings: World_Settings = WORLD_DEFAULT_SETTINGS,
	allocator: runtime.Allocator = context.allocator,
) -> ^World {
	world := new(World, allocator)
	world.allocator = allocator
	world.settings = settings
	// SHARED ENTITY NAMESPACE
	ode.overbase_init(
		&world.overbase,
		settings.entities_capacity,
		4, // Reserve room for multiple DB 
		allocator,
	)
	// Entity store
	entity_store_init(&world.entities, &world.overbase)
	// component registry
	component_registry_init(&world.registry, allocator, settings.gameplay.tables_capacity)
	//* GAMEPLAY
	// This DB shares the overbase rather than creating it's own entity namespace.
	if !database_init(
		&world.gameplay,
		&world.overbase,
		.Gameplay,
		"Gameplay",
		allocator,
		settings.gameplay.tables_capacity,
		settings.gameplay.views_capacity,
		settings.gameplay.tables_capacity,
		settings.gameplay.pair_tables_capacity,
		settings.gameplay.command_buffers_capacity,
		settings.gameplay.observers_capacity,
	) {
		world_destroy(world)
		return nil
	}
	//* SPATIAL
	if !database_init(
		&world.spatial,
		&world.overbase,
		.Spatial,
		"Spatial",
		allocator,
		settings.spatial.tables_capacity,
		settings.spatial.views_capacity,
		settings.spatial.tables_capacity,
		settings.spatial.pair_tables_capacity,
		settings.spatial.command_buffers_capacity,
		settings.spatial.observers_capacity,
	) {
		world_destroy(world)
		return nil
	}
	//* NETWORK
	if !database_init(
		&world.network,
		&world.overbase,
		.Network,
		"Network",
		allocator,
		settings.network.tables_capacity,
		settings.network.views_capacity,
		settings.network.tables_capacity,
		settings.network.pair_tables_capacity,
		settings.network.command_buffers_capacity,
		settings.network.observers_capacity,
	) {
		world_destroy(world)
		return nil
	}
	//* EDITOR
	if !database_init(
		&world.editor,
		&world.overbase,
		.Editor,
		"Editor",
		allocator,
		settings.editor.tables_capacity,
		settings.editor.views_capacity,
		settings.editor.tables_capacity,
		settings.editor.pair_tables_capacity,
		settings.editor.command_buffers_capacity,
		settings.editor.observers_capacity,
	) {
		world_destroy(world)
		return nil
	}

	//* COMMAND BUFFERS
	// The scheduler will overwrite the cap with the worker count.
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
	world_destroy_views(world)
	world_destroy_command_buffers(world)

	database_destroy(&world.editor)
	database_destroy(&world.network)
	database_destroy(&world.spatial)
	database_destroy(&world.gameplay)
	database_destroy(&world.custom)

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
	if world == nil || entity == nil do return false
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
	database: Database_Kind,
	name: string,
	table: ^ode.Table(T),
	flags: Component_Flags = {.Runtime},
) -> Component_ID {
	assert(world != nil)
	return component_register_table(T, &world.registry, database, name, table, flags)
}

//* Command Buffer Initialization
world_init_command_buffers :: proc(world: ^World) -> bool {
	if world == nil do return false
	count := world.settings.gameplay.command_buffers_capacity
	if count <= 0 do return false
	world.command_buffers = make([]ode.Command_Buffer, count, world.allocator)
	for i in 0 ..< count {
		if err := ode.command_buffer__init(
			&world.command_buffers[i],
			&world.gameplay.ecs,
			world.settings.command_buffer_commands,
			world.settings.command_buffer_payload,
		); err != nil {
			// Terminate everything already initialized.
			for j in 0 ..< i {ode.command_buffer__terminate(&world.command_buffers[j])}
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

//* VIEWS
world_view_create :: proc(
	world: ^World,
	database: Database_Kind,
	name: string,
	includes: []^ode.Shared_Table,
	excludes: []^ode.Shared_Table = nil,
	any_of: []^ode.Shared_Table = nil,
	filter: proc(row: ^ode.View_Row, user_data: rawptr) -> bool = nil,
) -> ^View {
	if world == nil do return nil
	db := world_database(world, database)
	if db == nil || !db.initialized do return nil
	view := new(View, world.allocator)
	if !view_init(view, db, name, includes, excludes, any_of, filter) {
		free(view, world.allocator)
		return nil
	}
	append(&world.views.all, view)
	return view
}
world_destroy_views :: proc(world: ^World) {
	if world == nil do return
	views := &world.views

	for v in world.views.all {view_destroy(v)}
	for v in world.views.all {if v != nil do free(v, world.allocator)}
	delete(world.views.all)

	view_destroy(views.chunk_membership)
	view_destroy(views.render_models)
	view_destroy(views.replication)
	view_destroy(views.spatial_bounds)
	view_destroy(views.transforms)

	if world.views.transforms != nil {free(world.views.transforms, world.allocator)}
	if world.views.render_models != nil {free(world.views.render_models, world.allocator)}
	if world.views.chunk_membership != nil {free(world.views.chunk_membership, world.allocator)}
	if world.views.spatial_bounds != nil {free(world.views.spatial_bounds, world.allocator)}
	if world.views.replication != nil {free(world.views.replication, world.allocator)}

	views^ = {}
}