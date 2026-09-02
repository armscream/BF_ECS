// Engine/src/Modules/BF_ECS/Entity.odin
package BF_ECS

import ode "/ode_ecs/src"

//* Entity
// BF_ECS entities are ODE_ECS entities. 
Entity :: ode.entity_id

// ODE_ECS uses DELETED_INDEX for invalid/expired IDs.
ENTITY_INVALID :: Entity {
	ix = ode.DELETED_INDEX
}

//* ENTITY STORE
// ODE Overbase holds entity lifetime, while several ode databases can share the same entity namespace.
Entity_Store :: struct {
	overbase: ^ode.Overbase
}

//* INITIALIZATION
entity_store_init :: proc(store: ^Entity_Store, overbase: ^ode.Overbase) {
	assert(store != nil)
	assert(overbase != nil)
	store.overbase = overbase
}
entity_store_destroy :: proc(store: ^Entity_Store){
	if store == nil do return
	store^ = {}
}

//* CREATION / DESTRUCTION
entity_create :: proc(store: ^Entity_Store) -> Entity {
	assert(store != nil)
	assert(store.overbase != nil)

	entity, err := ode.create_entity(store.overbase)
	if err != nil do return ENTITY_INVALID
	return entity
}
entity_destroy :: proc(store: ^Entity_Store, entity: Entity) -> bool {
	if store == nil || store.overbase == nil do return false
	if !entity_is_alive(store, entity) do return false
	err := ode.destroy_entity(store.overbase, entity)

	return err == nil
}

//* VALIDATION
entity_is_alive :: proc(store: ^Entity_Store, entity: Entity) -> bool {
	if store == nil || store.overbase == nil do return false
	if entity == ENTITY_INVALID do return false
	return !ode.is_expired(store.overbase, entity)
}

//* UTILITY
entity_count :: proc(store: ^Entity_Store) -> int {
	if store == nil || store.overbase == nil do return 0
	return ode.entities_len(store_overbase)
}