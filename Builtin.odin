// Engine/src/Modules/BF_ECS/Builtin.odin
//
// Built-in component tables.
//
// Every built-in BF_ECS component declared in Schema.odin gets exactly one
// concrete ODE table per owning database, created here and published through
// the world's Component_Registry. Consumers (renderer extraction, replication,
// editor tooling) never create these tables themselves; they resolve a
// Component_Binding from the registry, which keeps the component -> storage
// mapping in one place.
//
// Database ownership:
//   Gameplay : Transform, Render_Model, Render_Material_Override,
//              Camera, Camera_Active, Light
//   Spatial  : Chunk_Membership, Spatial_Bounds, Spatial_State
//
// The tables live inline on the World. ODE terminates every table attached to
// a database when that database is terminated, so `world_destroy` already
// tears them down; there is no separate teardown entry point here.

package BF_ECS

import ode "/ode_ecs/src"

//* BUILT-IN COMPONENT NAMES
// Stable registry names. Renaming one is an API break for anything that
// resolves components by name instead of by type.
COMPONENT_NAME_TRANSFORM :: "Transform"
COMPONENT_NAME_RENDER_MODEL :: "Render_Model"
COMPONENT_NAME_RENDER_MATERIAL_OVERRIDE :: "Render_Material_Override"
COMPONENT_NAME_CHUNK_MEMBERSHIP :: "Chunk_Membership"
COMPONENT_NAME_SPATIAL_BOUNDS :: "Spatial_Bounds"
COMPONENT_NAME_SPATIAL_STATE :: "Spatial_State"
COMPONENT_NAME_CAMERA :: "Camera"
COMPONENT_NAME_CAMERA_ACTIVE :: "Camera_Active"
COMPONENT_NAME_LIGHT :: "Light"

//* DEFAULT TABLE CAPACITY
// Per-table row capacity. ODE tables are fixed-capacity, so this is the
// maximum number of entities that may carry a given built-in component.
BUILTIN_COMPONENT_DEFAULT_CAPACITY :: 4096

//* BUILT-IN TABLES
// Owned by the World; registered into the Component_Registry so type-erased
// consumers can reach them through Component_Binding.
Builtin_Tables :: struct {
	transform:         ode.Table(Transform),
	render_model:      ode.Table(Render_Model),
	material_override: ode.Table(Render_Material_Override),
	chunk_membership:  ode.Table(Chunk_Membership),
	spatial_bounds:    ode.Table(Spatial_Bounds),
	spatial_state:     ode.Table(Spatial_State),
	camera:            ode.Table(Camera),
	camera_active:     ode.Table(Camera_Active),
	light:             ode.Table(Light),
}

//* REGISTRATION
// Creates and registers every built-in component table. Idempotent: calling it
// twice on the same world is a no-op that reports success.
//
// On partial failure the tables that were already created stay attached to
// their database and are terminated by `world_destroy`; the world is left
// unflagged so a caller that ignores the result cannot observe a half-built
// registry as complete.
world_register_builtin_components :: proc(
	world: ^World,
	capacity: int = BUILTIN_COMPONENT_DEFAULT_CAPACITY,
) -> bool {
	if world == nil do return false
	if world.builtin_registered do return true
	if capacity <= 0 do return false

	b := &world.builtin

	//* GAMEPLAY
	if !builtin_table_register(
		Transform,
		world,
		.Gameplay,
		COMPONENT_NAME_TRANSFORM,
		&b.transform,
		capacity,
		{.Runtime, .Editor_Visible, .Serializable, .Replicable},
	) {
		return false
	}

	if !builtin_table_register(
		Render_Model,
		world,
		.Gameplay,
		COMPONENT_NAME_RENDER_MODEL,
		&b.render_model,
		capacity,
		{.Runtime, .Editor_Visible, .Serializable},
	) {
		return false
	}

	if !builtin_table_register(
		Render_Material_Override,
		world,
		.Gameplay,
		COMPONENT_NAME_RENDER_MATERIAL_OVERRIDE,
		&b.material_override,
		capacity,
		{.Runtime, .Editor_Visible, .Serializable},
	) {
		return false
	}

	if !builtin_table_register(
		Camera,
		world,
		.Gameplay,
		COMPONENT_NAME_CAMERA,
		&b.camera,
		capacity,
		{.Runtime, .Editor_Visible, .Serializable},
	) {
		return false
	}

	if !builtin_table_register(
		Camera_Active,
		world,
		.Gameplay,
		COMPONENT_NAME_CAMERA_ACTIVE,
		&b.camera_active,
		capacity,
		{.Runtime, .Editor_Visible},
	) {
		return false
	}

	if !builtin_table_register(
		Light,
		world,
		.Gameplay,
		COMPONENT_NAME_LIGHT,
		&b.light,
		capacity,
		{.Runtime, .Editor_Visible, .Serializable},
	) {
		return false
	}

	//* SPATIAL
	if !builtin_table_register(
		Chunk_Membership,
		world,
		.Spatial,
		COMPONENT_NAME_CHUNK_MEMBERSHIP,
		&b.chunk_membership,
		capacity,
		{.Runtime, .Serializable, .Spatial},
	) {
		return false
	}

	if !builtin_table_register(
		Spatial_Bounds,
		world,
		.Spatial,
		COMPONENT_NAME_SPATIAL_BOUNDS,
		&b.spatial_bounds,
		capacity,
		{.Runtime, .Spatial},
	) {
		return false
	}

	if !builtin_table_register(
		Spatial_State,
		world,
		.Spatial,
		COMPONENT_NAME_SPATIAL_STATE,
		&b.spatial_state,
		capacity,
		{.Runtime, .Spatial, .Replicable},
	) {
		return false
	}

	world.builtin_registered = true
	return true
}

//* LEGACY ENTRY POINT
// Kept for callers that predate `world_register_builtin_components`.
register_built_in_components :: proc(world: ^World) -> bool {
	return world_register_builtin_components(world)
}

//* INTERNAL
@(private = "file")
builtin_table_register :: proc(
	$T: typeid,
	world: ^World,
	database: Database_Kind,
	name: string,
	table: ^ode.Table(T),
	capacity: int,
	flags: Component_Flags,
) -> bool {
	db := world_database(world, database)
	if db == nil || !db.initialized do return false
	if ode.table__init(table, &db.ecs, capacity) != nil do return false
	if world_register_component(T, world, database, name, table, flags) == COMPONENT_INVALID {
		ode.table__terminate(table)
		return false
	}
	return true
}

//* ACCESSORS
// Convenience typed access for engine code that already holds the World and
// does not want to go through the type-erased registry path.
world_builtin_tables :: #force_inline proc(world: ^World) -> ^Builtin_Tables {
	if world == nil || !world.builtin_registered do return nil
	return &world.builtin
}
