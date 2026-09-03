package BF_ECS

import ode "/ode_ecs/src"
import "base:runtime"

//* COMPONENT REGISTRY
Component_Registry :: struct {
	allocator:  runtime.Allocator,
	next_id:    Component_ID,
	components: [dynamic]Component_Descriptor,
	by_name:    map[string]Component_ID,
	by_type:    map[typeid]Component_ID,
}

//* INITIALIZATION
component_registry_init :: proc(
	registry: ^Component_Registry,
	allocator := context.allocator,
	capacity: int = 64,
) {
	assert(registry != nil)
	registry.allocator = allocator
	registry.next_id = Component_ID(1)
	registry.components = make([dynamic]Component_Descriptor, 0, capacity, allocator)
	registry.by_name = make(map[string]Component_ID, allocator)
	registry.by_type = make(map[typeid]Component_ID, allocator)
}
//* DESTRUCTION
component_registry_destroy :: proc(registry: ^Component_Registry) {
	if registry == nil do return
	delete(registry.components)
	delete(registry.by_name)
	delete(registry.by_type)
	registry^ = {}
}
//* REGISTER Table(T)
component_register_table :: proc(
	$T: typeid,
	registry: ^Component_Registry,
	name: string,
	table: ^ode.Table(T),
	flags: Component_Flags = {.Runtime},
) -> Component_ID {
	assert(registry != nil)
	assert(table != nil)
	assert(name != "")
	// existing name
	if existing, ok := registry.by_name[name]; ok {
		return existing
	}
	// existing type
	type_id := typeid_of(T)
	if exists, ok := registry.by_type[type_id]; ok {
		return exists
	}
	id := registry.next_id
	registry.next_id += 1

	descriptor := component_descriptor_table(T, id, name, table, flags)
	append(&registry.components, descriptor)
	registry.by_name[name] = id
	registry.by_type[type_id] = id

	return id
}
//* LOOKUP
component_find :: proc(registry: ^Component_Registry, id: Component_ID) -> ^Component_Descriptor {
	if registry == nil || id == COMPONENT_INVALID do return nil
	index := int(id)
	if index < 0 || index >= len(registry.components) do return nil
	return &registry.components[index]
}
component_find_by_name :: proc(
	registry: ^Component_Registry,
	name: string,
) -> ^Component_Descriptor {
	if registry == nil do return nil
	id, ok := registry.by_name[name]
	if !ok do return nil
	return component_find(registry, id)
}
component_find_by_type :: proc(
	$T: typeid,
	registry: ^Component_Registry,
) -> ^Component_Descriptor {
	if registry == nil do return nil
	id, ok := registry.by_type[typeid_of(T)]
	if !ok do return nil
	return component_find(registry, id)
}

//* COMPONENT ID
component_id :: proc($T: typeid, registry: ^Component_Registry) -> Component_ID {
	if registry == nil do return COMPONENT_INVALID
	id, ok := registry.by_type[typeid_of(T)]
	if !ok do return COMPONENT_INVALID
	return id
}

//* ENUMERATION
component_count :: proc(registry: ^Component_Registry) -> int {
	if registry == nil do return 0
	return len(registry.components)
}
component_at :: proc(registry: ^Component_Registry, index: int) -> ^Component_Descriptor {
	if registry == nil do return nil
	if index < 0 || index >= len(registry.components) do return nil
	return &registry.components[index]
}
