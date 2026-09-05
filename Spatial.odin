// BF_ECS/Spatial.odin
package BF_ECS

import "../../Core"
import ode "/ode_ecs/src"

Map_ID :: distinct u64
Chunk_ID :: distinct u64

Chunk_Component :: struct {
	chunk: Chunk_ID,
}

Map :: struct {
	id:            Map_ID,
	header:        Map_Header,
	chunks:        []Chunk_ID,
	entities:      []Entity,
	relationships: []ode.Relations_Table,
}

Map_Header :: struct {
	verion:       u32,
	id:           Map_ID,
	world_bounds: Core.AABB,
	chunk_size:   f32,
	chunk_count:  u32,
	entity_count: u32,
	flags:        Map_Flags,
}

Map_Flags :: bit_set[Map_Flag]
Map_Flag :: enum {}// empty for now


Map_Entity_Record :: struct {
	id:               Entity,
	chunk:            Chunk_ID,
	flags:            Entity_Flags,
	archetype:        ode.Arch_Table, //should be ode
	component_offset: u32,
}
