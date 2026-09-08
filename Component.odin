// Engine/src/Modules/BF_ECS/Component.odin
package BF_ECS

import ode "/ode_ecs/src"
import "base:runtime"

//* COMPONENT ID
// this is a BF_ECS schema ID, not an ode table_id.
// ode ECS table id's describe storage inside one database. Component_ID describes the engine-level component type.
// this distinction becomes important when the component exists in multiple databases.
Component_ID :: distinct u32
COMPONENT_INVALID :: Component_ID(0)

//* COMPONENT BINDING
Component_Binding :: struct {
	database: Database_Kind,
	storage:  Component_Storage,
	table:    rawptr,
	add:      Component_Add_Proc,
	get:      Component_Get_Proc,
	has:      Component_Has_Proc,
	remove:   Component_Remove_Proc,
}

//* COMPONENT DESCRIPTOR
Component_Descriptor :: struct {
	id:       Component_ID,
	name:     string,
	type_id:  typeid,
	size:     int,
	align:    int,
	flags:    Component_Flags,
	bindings: [dynamic]Component_Binding,
}

//* COMPONENT STORAGE
Component_Storage :: enum u8 {
	Table,
	Compact_Table,
	Tiny_Table,
	Tag_Table,
	Arch_Table,
}

//* COMPONENT REGISTRY
Component_Registry :: struct {
	allocator:  runtime.Allocator,
	next_id:    Component_ID,
	components: [dynamic]Component_Descriptor,
	by_name:    map[string]Component_ID,
	by_type:    map[typeid]Component_ID,
}

//* COMPONENT FLAGS
Component_Flags :: bit_set[Component_Flag]
Component_Flag :: enum u8 {
	// Component participates in normal gameplay ECS storage.
	Runtime,
	// Component is visible to editor tooling.
	Editor_Visible,
	// Component may be serialized into project/world data.
	Serializable,
	// Component is eligible for replication.
	Replicable,
	Singleton,
	// Component is safe to use as a tag.
	Tag,
	// Component participates in spatial queries.
	Spatial,
}

//* TYPE-ERASED COMPONENT OPERATIONS
// These are the engine-facing operations.
// Gameplay code should normally use typed ODE_ECS APIs: ode.add_component(&transform_table, entity). // TODO: gameplay ECS reflection in SDK.
// Editor/module/reflection code can instead operate through Component_ID.
Component_Add_Proc :: proc(table: rawptr, entity: Entity) -> rawptr
Component_Get_Proc :: proc(table: rawptr, entity: Entity) -> rawptr
Component_Remove_Proc :: proc(table: rawptr, entity: Entity) -> bool
Component_Has_Proc :: proc(table: rawptr, entity: Entity) -> bool

//* GENERIC TABLE OPERATIONS
//renamed from component_add
component_add_table :: proc($T: typeid, table: rawptr, entity: Entity) -> rawptr {
	t := cast(^ode.Table(T))table
	component, err := ode.add_component(t, entity)
	if err != nil do return nil
	return cast(rawptr)component
}
//renamed from component_get
component_get_table :: proc($T: typeid, table: rawptr, entity: Entity) -> rawptr {
	t := cast(^ode.Table(T))table
	component := ode.get_component(t, entity)
	return cast(rawptr)component
}
// renamed from component_has
component_has_table :: proc($T: typeid, table: rawptr, entity: Entity) -> bool {
	t := cast(^ode.Table(T))table
	return ode.has_component(t, entity)
}
// renamed from component_remove
component_remove_table :: proc($T: typeid, table: rawptr, entity: Entity) -> bool {
	t := cast(^ode.Table(T))table
	err := ode.remove_component(t, entity)
	return err == nil
}
component_find_table :: proc(
	registry: ^Component_Registry,
	id: Component_ID,
	database: Database_Kind,
) -> rawptr {
	descriptor := component_find(registry, id)
	binding := component_binding_find(descriptor, database)
	if binding == nil do return nil
	return binding.table
}
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
		id = existing
	} else {
		id = registry.next_id
		registry.next_id += 1
		descriptor := Component_Descriptor {
			id      = id,
			name    = name,
			type_id = type_id,
			size    = sizeof(T),
			align   = alignof(T),
			flags   = flags,
		}
		append(&registry.components, descriptor)

		registry.by_name[name] = id
		registry.by_type[type_id] = id
	}
	descriptor := component_find(registry, id)
	assert(descriptor != nil)

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
	if !component_binding_add(descriptor, binding) {return id}
	return id
}

component_binding_find :: proc(
	descriptor: ^Component_Descriptor,
	database: Database_Kind,
) -> ^Component_Binding {
	if descriptor == nil do return nil
	for &binding in descriptor.bindings {
		if binding.database == database {
			return &binding
		}
	}
	return nil
}
component_binding_add :: proc(
	descriptor: ^Component_Descriptor,
	binding: Component_Binding,
) -> bool {
	if descriptor == nil do return false
	if component_binding_find(descriptor, binding.database) != nil do return false
	append(&descriptor.bindings, binding)
	return true
}

//* DESCRIPTOR CONSTRUCTION
// the caller owns the actual Table(T). The registry does not dynamically construct arbitrary odin types
// Odin's comp time generic system constructs the typed table and then registers it's erased representation here.
component_descriptor_table :: proc(
	$T: typeid,
	id: Component_ID,
	name: string,
	table: ^ode.Table(T),
	flags: Component_Flags,
) -> Component_Descriptor {
	return Component_Descriptor {
		.id = id,
		.name = name,
		.type_id = typeid_of(T),
		.size = sizeof(T),
		.align = alignof(T),
		.flags = flags,
		table = cast(rawptr)table,
		add = proc(table: rawptr, entity: Entity) -> rawptr {return component_add_table(
				T,
				table,
				entity,
			)},
		get = proc(table: rawptr, entity: Entity) -> rawptr {return component_get_table(
				T,
				table,
				entity,
			)},
		has = proc(table: rawptr, entity: Entity) -> bool {component_has_table(T, table, entity)},
		remove = proc(table: rawptr, entity: Entity) -> bool {component_remove_table(
				T,
				table,
				entity,
			)},
	}
}
