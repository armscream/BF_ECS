package BF_ECS

import ode "/ode_ecs/src"

//* DATABASE KIND
Database_Kind :: enum u8 {
	Gameplay,
	Spatial,
	Network,
	Editor,
	Custom,
}

//* BF_ECS DATABASE
// this is a thin ownership/identity layer around an ode database.
// BF owns the database lifetime. ODE owns the ECS storage.
Database :: struct {
	kind:        Database_Kind,
	name:        string,
	ecs:         ode.Database,
	initialized: bool,
}
//* INITIALIZATION
database_init :: proc(
	db: ^Database,
	overbase: ^ode.Overbase,
	kind: Database_Kind,
	name: string,
	allocator := context.allocator,
	entities_tables_cap: int = 128,
	views_cap: int = 64,
	tiny_tables_cap: int = 32,
	pair_tables_cap: int = 8,
	command_buffers_cap: int = 32,
	observers_cap: int = 8,
) -> bool {
	assert(db != nil)
	assert(overbase != nil)
	if db.initialized do return false

	err := ode.init_from_overbase(
		&db.ecs,
		overbase,
		allocator,
		entities_tables_cap,
		views_cap,
		tiny_tables_cap,
		pair_tables_cap,
		command_buffers_cap,
		observers_cap,
	)
	if err != nil do return false
	db.kind = kind
	db.name = name
	db.initialized = true
	return true
}
//* TERMINATION
database_destroy :: proc(db: ^Database) {
	if db == nil || !db.initialized do return
	// This detaches the db from the shared Overbase.
	ode.terminate(&db.ecs)
	db^ = {}
}
//* VALIDATION
database_is_valid :: proc(db: ^Database) -> bool {
	if db == nil || !db.initialized do return false
	return ode.is_valid(&db.ecs)
}
