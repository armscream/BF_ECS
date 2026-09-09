// BF_ECS/Scene.odin
package BF_ECS

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
    by_id: map[Chunk_ID]u32,
    runtime: [dynamic]Chunk_Runtime,
}