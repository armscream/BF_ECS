// Engine/src/Modules/BF_ECS/Component.odin
package BF_ECS

import "base:runtime"
import ode "/ode_ecs/src"

//* COMPONENT ID
// this is a BF_ECS schema ID, not an ode table_id. 
// ode ECS table id's describe storage inside one database. Component_ID describes the engine-level component type.
// this distinction becomes important when the component exists in multiple databases.

Component_ID :: distinct u32
COMPONENT_INVALID :: Component_ID(0)

//* COMPONENT FLAGS
Component_Flags :: bit_set[Component_Flag; u8]
Component_Flag :: enum u8 {
    None,
    // Component participates in normal gameplay ECS storage.
    Runtime,
    // Component is visible to editor tooling.
    Editor_Visible,
    // Component may be serialized into project/world data.
    Serializable,
    // Component is safe to use as a tag.
    Tag,
    // Component participates in spatial queries.
    Spatial,
    // Component is eligible for replication.
    Replicable,
}

//* TYPE-ERASED COMPONENT OPERATIONS
Component_Add_Proc :: proc(table: rawptr, entity: Entity) -> rawptr
Component_Get_Proc :: proc(table: rawptr, entity: Entity) -> rawptr
Component_Get_Mut_Proc :: proc(table: rawptr, entity: Entity) -> rawptr
Component_Remove_Proc :: proc(table: rawptr, entity: Entity) -> bool
Component_Has_Proc :: proc(table: rawptr, entity: Entity) -> bool
Component_Clear_Proc :: proc(table: rawptr, entity: Entity) -> bool

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
    flags: Component_Flags,
    // The ODE_ECS Table(T) backing this component in the associated DB
    table: rawptr,
    // Type-erased operations.
    add: Component_Add_Proc,
    get: Component_Get_Proc,
    get_mut: Component_Get_Mut_Proc,
    remove: Component_Remove_Proc,
    has: Component_Has_Proc,
    clear: Component_Clear_Proc,
}

//* GENERIC TABLE OPERATIONS
component_add :: proc($T: typeid, table: rawptr, entity: Entity) -> rawptr {
    t := cast(^ode.Table(T))table
    component, err := ode.add_component(t, entity)
    if err != nil {
        // Component_Already_Exist still gives us the existing component
        // for the type-erased API, returning that pointer is useful.
        if err == ode.API_Error.Component_Already_Exist {
            return cast(rawptr)component
        }
        return nil
    }
    return cast(rawptr)component
}
component_get :: proc($T: typeid, table: rawptr, entity: Entity) -> rawptr {
    t := cast(^ecs.Table(T))table
    component := ode.get_component(t, entity)
    return cast(rawptr)component
}
component_remove :: proc($T: typeid, table: rawptr, entity: Entity) -> bool {
    t := cast(^ode.Table(T))table
    err := ode.remove_component(t, entity)
    return err == nil
}
component_has :: proc($T: typeid, table: rawptr, entity: Entity) -> bool {
    t := cast(^ode.Table(T))table
    err := ode.clear(t)
    return err == nil
}
component_clear :: proc($T: typeid, table: rawptr) -> bool {
    t := cast(^ode.Table(T))table
    err := ode.clear(t)
    return err == nil
}

//* GENERIC COMPONENT DESCRIPTION
// the caller owns the actual Table(T). The registry does not dynamically construct arbitrary odin types
// Odin's comp time generic system constructs the typed table and then registers it's erased representation here.
component_descriptor :: proc($T: typeid, id: Component_ID, name: string, table: ^ode.Table(T), flags: Component_Flags) -> Component_Descriptor {
    return Component_Descriptor{
        .id = id,
        .name = name,
        .type_id = typeid_of(T),
        .size = sizeof(T),
        .align = alignof(T),
        .flags = flags,

        table = cast(rawptr)table,

        add = proc(table: rawptr, entity: Entity) -> rawptr {return component_add(T, table, entity)},
        get_mut = proc(table: rawptr, entity: Entity) -> rawptr {return component_get_mut(T, table, entity)},
        remove = proc(table: rawptr, entity: Entity) -> bool {component_remove(T, table, entity)},
        has = proc(table: rawptr, entity: Entity) -> bool {component_has(T, table, entity)},
        clear = proc(table: rawptr) -> bool {component_clear(T, table)},
    }
}