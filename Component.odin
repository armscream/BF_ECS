// Engine/src/Modules/BF_ECS/Component.odin
package BF_ECS

import ode "/ode_ecs/src"

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

//* COMPONENT DESCRIPTOR
Component_Descriptor :: struct {
    id: Component_ID,
    // Stable engine/editor identifier. 
    name: string,
    // Odin's runtime type id.
    type_id: typeid,
    // Useful for reflection/editor/serialization.
    size: int,
    align: int,
    storage: Component_Storage,
    flags: Component_Flags,
    // User-owned Ode table.
    table: rawptr,
    // Type-erased operations.
    add: Component_Add_Proc,
    get: Component_Get_Proc,
        has: Component_Has_Proc,
    remove: Component_Remove_Proc,
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
//* DESCRIPTOR CONSTRUCTION
// the caller owns the actual Table(T). The registry does not dynamically construct arbitrary odin types
// Odin's comp time generic system constructs the typed table and then registers it's erased representation here.
component_descriptor_table :: proc($T: typeid, id: Component_ID, name: string, table: ^ode.Table(T), flags: Component_Flags) -> Component_Descriptor {
    return Component_Descriptor{
        .id = id,
        .name = name,
        .type_id = typeid_of(T),
        .size = sizeof(T),
        .align = alignof(T),
        .flags = flags,

        table = cast(rawptr)table,

        add = proc(table: rawptr, entity: Entity) -> rawptr {return component_add_table(T, table, entity)},
        get = proc(table: rawptr, entity: Entity) -> rawptr {return component_get_table(T, table, entity)},
        has = proc(table: rawptr, entity: Entity) -> bool {component_has_table(T, table, entity)},
        remove = proc(table: rawptr, entity: Entity) -> bool {component_remove_table(T, table, entity)},
    }
}