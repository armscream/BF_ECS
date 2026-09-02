// Engine/src/Modules/BF_ECS/Entity.odin
package BF_ECS

import "core:encoding/entity"
import hm "core:container/handle_map"
import "core:mem"

// Entity with generational handles, will itterate further on this.
Entity :: hm.Handle64
ENTITY_INVALID :: Entity{}

Entity_Record :: struct {
	handle:    Entity,
	//placeholder for archetype or ECS storage location.
	archetype: u32,
	row:       u32,
}

Entity_Manager :: struct {
	allocator:   mem.Allocator,
	entities:    hm.Dynamic_Handle_Map(Entity_Record, Entity),
	alive_count: u32,
}
entity_manager_init :: proc(manager: ^Entity_Manager, allocator: mem.Allocator) {
	manager.allocator = allocator
	hm.dynamic_init(&manager.entities, allocator)
	manager.alive_count = 0
}
entity_manager_destroy :: proc(manager: ^Entity_Manager) {
	hm.dynamic_destroy(&manager.entities)
	manager^ = {}
}

entity_create :: proc(manager: ^Entity_Manager) -> Entity {
	record :=  Entity_Record{}
	entity, err := hm.add(&manager.entities, record)
	assert(err == nil, "BF_ECS: Failed to allocate entity handle.") // TODO: Should i use log.error here?

	record.handle  = entity
	if stored, ok := hm.get(&manager.entities, entity); ok{stored^ = record}
	manager.alive_count += 1
	return entity
}
entity_destroy :: proc(manager: ^Entity_Manager, entity: Entity) -> bool {
	// TODO: Destroy entity
	return ok
}