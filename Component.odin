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

//* COMPONENT STORAGE
Component_Storage :: enum u8 {
	Table,
	Compact_Table,
	Tiny_Table,
	Tag_Table,
	Arch_Table,
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

//* COMPONENT BINDING
// A component type may have multiple storage instances. Ex: Transform: Gameplay -> Table(Transform), Editor -> Table(Transform)
// Component ID identifies Transform. Component_Binding identifies one concrete storage instance.
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
component_binding_get :: proc(
	registry: ^Component_Registry,
	id: Component_ID,
	database: Database_Kind,
) -> ^Component_Binding {
	if registry == nil do return nil
	descriptor := component_find(registry, id)
	if descriptor == nil do return nil
	return component_binding_find(descriptor, database)
}
component_table :: proc(
	registry: ^Component_Registry,
	id: Component_ID,
	database: Database_Kind,
) -> rawptr {
	binding := component_binding_get(registry, id, database)
	if binding == nil do return nil
	return binding.table
}