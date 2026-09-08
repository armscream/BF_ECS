// BF_ECS/Scene.odin
package BF_ECS

import mth "../../Core/BF_Math"
import "../../Core"
import hm "core:container/handle_map"
import "base:runtime"

Map_ID :: distinct u64
MAP_INVALID :: Map_ID(0)
Map_Flags :: bit_set[Map_Flag]
Map_Flag :: enum u8 {
    Streaming,
    Persistent,
    Editor,
    Runtime,
}
Map :: struct {
    id: Map_ID,
    name: string,
    bounds: mth.AABB
    chunk_size: mth.Vec3,
    flags: Map_Flags,
    chunks: [dynamic]Map_Chunk,
    asset_dependencies: [dynamic]Core.Asset_Ref,
}
Map_Chunk :: struct {
    id: Chunk_ID,
    bounds: mth.AABB,
    flags: Chunk_Flags,
    entity_count: u32,
    asset_dependency_offset: u32,
    asset_dependency_count: u32,
}
Chunk_Flags :: bit_set[Chunk_Flag]
Chunk_Flag :: enum {
	Persistent,
    Streamable,
    Loaded,
    Visible,
    Simulated,
    Replicated,
    Baked,
}
Map_Chunk_Entity :: struct {
    entity: Entity,
}

Chunk_Runtime_State :: enum u8 {
    Unloaded,
    Loading,
    Loaded,
    Activating,
    Active,
    Unloading,
}
Chunk_Runtime :: struct {
    id: Chunk_ID,
    state: Chunk_Runtime_State,
    entity_count: u32,
    loaded_tick: u64,
    last_used_tick: u64,
}
Chunk_Store :: struct {
    allocator: runtime.Allocator,
    chunks: [dynamic]Map_Chunk,
    by_id: hm.Handle_Map(Chunk_ID, u32),
    runtime: [dynamic]Chunk_Runtime,
}