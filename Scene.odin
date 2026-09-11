// BF_ECS/Scene.odin
package BF_ECS

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