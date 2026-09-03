// BF_ECS/View.odin
package BF_ECS

import ode "/ode_ecs/src"

//* View
// A view is a persistent query object. It is created during world/database setup and then reused every frame.
// Do NOT create views inside the frame loop.
// ODE_ECS automatically updates a view when structural changes occur.
View :: struct {
    name: string,
    ecs: ode.View,
    database: ^Database,
    initialized: bool,
}

//* Initialization
view_init :: proc(view: ^View, database: ^Database, name: string, includes: []^ode.Shared_Table, excludes: []^ode.Shared_Table = nil, any_of: []^ode.Shared_Table = nil, filter: proc(row: ^ode.View_Row, user_data: rawptr)->bool = nil) -> bool {
    assert(view != nil)
    assert(database != nil)
    assert(database.initialized)
    if view.initialized do return false
    if includes == nil || len(includes) == 0 do return false
    err := ode.view__init(&view.ecs, &database.ecs, includes, excludes, any_of, filter)
    if err != nil do return false
    view.name = name
    view.database = database
    view.initialized = true
    return true
}

//* Destruction
view_destroy :: proc(view: ^View) {
    if view == nil || !view.initialized do return
    ode.view_terminate(&view.ecs)
    view^ = {}
}

//* State
view_is_valid :: proc(view: ^View) -> bool {
    if view == nil || !view.initialized do return false
    return view.ecs.state == ode.Object_State.Normal
}
view_len :: #force_inline proc(view: ^View) -> int {
    if view == nil || !view.initialized do return 0
    return ode.view_len(&view.ecs)
}
view_cap :: #force_inline proc(view: ^View) -> int {
    if view == nil || !view.initialized do return 0
    return ode.view_cap(&view.ecs)
}

//* Entities
// this returns the View's curent dense entity array.
//* WARNING
// Structural changed can invalidate the view's row ordering. Systems should not retain
// this slice across structual synch points.
view_entities :: #force_inline proc(view: ^View) -> []Entity {
    if view == nil || !view.initialized do return nil
    return ode.view_entities_slice(&view.ecs)
}

//* Typed Component Slice
// This is the normal high-performance BF_ECS path.
// OCE_ECS stores a pointer cacher per view column. This proc exposes the typed slice over that cache.
// for max perf where possible, use view_try_dense instead.
view_column :: #force_inline proc($T: typeid, view: ^View) -> []^T {
    if view == nil || !view.initialized do return nil
    return ode.view_column_slice(&view.ecs, T)
}

//* Dense Component Slice
// If the underlying Table(T) is currently aligned with the View, ODE_ECS can return 
// the table's actual []T storage.
// This removes the per-row raw-pointer indirection.
// If the view is not aligned, this returns nil.
view_try_dense :: #force_inline proc($T: typeid, view: ^View, table: ^ode.Table(T)) -> []T {
    if view == nil || !view.initialized || table == nil do return nil
    return ode.view__try_dense_slice(&view.ecs, table)
}

//* Rebuild / Filtering
view_rebuild :: proc(view: ^View) -> bool {
    if view == nil || !view.initialized do return false
    err:= ode.rebuild(&view.ecs)
    return err == nil
}
view_refilter :: proc(view: ^View) -> bool {
    if view == nil || !view.initialized do return false
    err:= ode.refilter(&view.ecs)
    return err == nil
}
view_rerun_filter :: proc(view: ^View, entity: Entity)  -> bool {
    if view == nil || !view.initialized do return false
    err:= ode.rerun_filter(&view.ecs, entity)
    return err == nil
}

//* Suspend / Resume
// Suspending stops automatic structural updates.
// After resume, ODE_ECS may need to rebuild/refill the view depending on what 
// happened during suspension.
view_suspend :: proc(view: ^View) {
    if view == nil || !view.initialized do return
    ode.suspend(&view.ecs)
}
view_resume :: proc(view: ^View) {
    if view == nil || !view.initialized do return
    ode.resume(&view.ecs)
}
