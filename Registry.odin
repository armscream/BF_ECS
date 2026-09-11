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
	for &descriptor in registry.components {
		if len(descriptor.bindings) > 0 {delete(descriptor.bindings)}
	}
	delete(registry.components)
	delete(registry.by_name)
	delete(registry.by_type)
	registry^ = {}
}
//* REGISTER Table(T)
component_register_table :: proc(
	$T: typeid,
	registry: ^Component_Registry,
	database: Database_Kind,
	name: string,
	table: ^ode.Table(T),
	flags: Component_Flags = {.Runtime},
) -> Component_ID {
	assert(registry != nil)
	assert(table != nil)
	assert(name != "")
	type_id := typeid_of(T)
	id := COMPONENT_INVALID
	if existing, ok := registry.by_type[type_id]; ok {
		id = existing
	} else if existing, ok := registry.by_name[name]; ok {
		// name collision with dif type is invalid
		if descriptor := component_find(registry, existing); descriptor != nil {
			if descriptor.type_id != type_id {
				return COMPONENT_INVALID
			}
		}
		id = existing
	} else {
		id = registry.next_id
		registry.next_id += 1
		descriptor := Component_Descriptor {
			id      = id,
			name    = name,
			type_id = type_id,
			size    = size_of(T),
			align   = align_of(T),
			flags   = flags,
		}
		append(&registry.components, descriptor)

		registry.by_name[name] = id
		registry.by_type[type_id] = id
	}
	descriptor := component_find(registry, id)
	if descriptor == nil do return COMPONENT_INVALID

	if existing := component_binding_find(descriptor, database); existing != nil do return id

	binding := Component_Binding {
		database = database,
		storage = .Table,
		table = cast(rawptr)table,
		add = proc(table: rawptr, entity: Entity) -> rawptr {
			return component_add_table(T, table, entity)
		},
		get = proc(table: rawptr, entity: Entity) -> rawptr {
			return component_get_table(T, table, entity)
		},
		has = proc(table: rawptr, entity: Entity) -> bool {
			return component_has_table(T, table, entity)
		},
		remove = proc(table: rawptr, entity: Entity) -> bool {
			return component_remove_table(T, table, entity)
		},
	}
	append(&descriptor.bindings, binding)
	descriptor.flags |= flags
	return id
}
//* LOOKUP
component_find :: proc(registry: ^Component_Registry, id: Component_ID) -> ^Component_Descriptor {
	if registry == nil || id == COMPONENT_INVALID do return nil
	index := int(id) - 1
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

//* REGISTER BUILT-IN COMPONENTS
// See Builtin.odin: `world_register_builtin_components` owns the concrete
// table construction and registry publication for every built-in component.

