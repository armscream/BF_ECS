// Engine/src/Modules/BF_ECS/Commands.odin
package BF_ECS

import ode "/ode_ecs/src"

//* Command Buffer
// BF_ECS does not implement another command system.
// ODE_ECS already has the correct deferred structural mutation model.
// BF_ECS merely gives it a stable engine-facing owner/name and hides the
// underlying ODE database plumbing.
Command_Buffer :: struct {
	name:        string,
	ecs:         ode.Command_Buffer,
	database:    ^Database,
	initialized: bool,
}

//* Initialization
command_buffer_init :: proc(
	buffer: ^Command_Buffer,
	database: ^Database,
	name: string,
	commands_capacity: int = 4096,
	payload_capacity: int = 256 * 1024,
) -> bool {
	assert(buffer != nil)
	assert(database != nil)
	assert(database.initialized)
	if buffer.initialized do return false

	err := ode.command_buffer_init(&buffer.ecs, &database.ecs, commands_capacity, payload_capacity)
	if err != nil do return false

	buffer.name = name
	buffer.database = database
	buffer.initialized = true

	return true
}

//* Destruction
command_buffer_destroy :: proc(buffer: ^Command_Buffer) {
	if buffer == nil || !buffer.initialized do return
	ode.command_buffer_terminate(&buffer.ecs)
	buffer^ = {}
}

//* State
command_buffer_is_valid :: proc(buffer: ^Command_Buffer) -> bool {
	if buffer == nil || !buffer.initialized do return false
	return true
}
command_buffer_len :: #force_inline proc(buffer: ^Command_Buffer) -> int {
	if buffer == nil || !buffer.initialized do return 0
	return ode.command_buffer_len(&buffer.ecs)
}
command_buffer_cap :: #force_inline proc(buffer: ^Command_Buffer) -> int {
	if buffer == nil || !buffer.initialized do return 0
	return ode.command_buffer_cap(&buffer.ecs)
}

//* Clear
command_buffer_clear :: proc(buffer: ^Command_Buffer) {
	if buffer == nil || !buffer.initialized do return
	ode.clear(&buffer.ecs)
}

//* Entity Creation
//TODO: Move this to entity_create(world) as this doesnt actually need the cmd buffer
// Entity creation is intentionally immediate.
// ODE_ECS explicitly does this because allocating an Entity ID does not
// mutate tables/views and is therefore safe during iteration.
// Components should then be added through the command buffer.
@(deprecated = "will be moved to entity_create(world) as entity creation is immediate")
command_buffer_create_entity :: proc(buffer: ^Command_Buffer) -> Entity {
	if buffer == nil || !buffer.initialized do return ENTITY_INVALID
	entity, err := ode.create_entity(buffer.database.ecs.overbase)
	if err != nil do return ENTITY_INVALID
	return entity
}

//* Destroy Entity
command_buffer_destroy_entity :: proc(
	buffer: ^Command_Buffer,
	entity: Entity,
	destroy_children: bool = false,
) -> bool {
	if buffer == nil || !buffer.initialized do return false
	err := ode.cmd_destroy_entity(&buffer.ecs, entity, destroy_children)
	return err == nil
}

//* Add Component
command_buffer_add :: proc(
	$T: typeid,
	buffer: ^Command_Buffer,
	table: ^ode.Table(T),
	entity: Entity,
	value: T,
) -> bool {
	if buffer == nil || !buffer.initialized || table == nil do return false
	err := ode.cmd_add_component(&buffer.ecs, table, entity, value)
	return err == nil
}

//* Remove Component
command_buffer_remove :: proc(
	$T: typeid,
	buffer: ^Command_Buffer,
	table: ^ode.Table(T),
	entity: Entity,
) -> bool {
	if buffer == nil || !buffer.initialized || table == nil do return false
	err := ode.cmd_remove_component(&buffer.ecs, table, entity)
	return err == nil
}

//* Add Tag
command_buffer_add_tag :: proc(
	buffer: ^Command_Buffer,
	table: ^ode.Tag_Table,
	entity: Entity,
) -> bool {
	if buffer == nil || !buffer.initialized || table == nil do return false
	err := ode.cmd_add_tag(&buffer.ecs, table, entity)
	return err == nil
}


//* Remove Tag
command_buffer_remove_tag :: proc(
	buffer: ^Command_Buffer,
	table: ^ode.Tag_Table,
	entity: Entity,
) -> bool {
	if buffer == nil || !buffer.initialized || table == nil do return false
	err := ode.cmd_remove_tag(&buffer.ecs, table, entity)
	return err == nil
}

//* Parenting
command_buffer_set_parent :: proc(buffer: ^Command_Buffer, child: Entity, parent: Entity) -> bool {
	if buffer == nil || !buffer.initialized do return false
	err := ode.cmd_set_parent(&buffer.ecs, child, parent)
	return err == nil
}

command_buffer_remove_parent :: proc(buffer: ^Command_Buffer, child: Entity) -> bool {
	if buffer == nil || !buffer.initialized do return false
	err := ode.cmd_remove_parent(&buffer.ecs, child)
	return err == nil
}

//* Replay
// This is the synchronization point.
// All structural operations recorded into this buffer become visible here.
command_buffer_replay :: proc(buffer: ^Command_Buffer) -> (skipped: int, success: bool) {
	if buffer == nil || !buffer.initialized do return 0, false
	count, err := ode.replay(&buffer.ecs)
	return count, err == nil
}
