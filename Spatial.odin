// BF_ECS/Spatial.odin
package BF_ECS

import "../../Core"
import ode "/ode_ecs/src"
import hm "core:container/handle_map"
import "core:container/queue"

Spatial_Database :: ode.Database
Network_Database :: ode.Database
Editor_Database :: ode.Database
Map_ID :: hm.Handle32
Chunk_ID :: hm.Handle32

Chunk_Store :: struct {
	chunks: [dynamic]Map_Chunk,
	by_id: [dynamic]Chunk_ID,
}

Chunk_Flags :: bit_set[Chunk_Flag]
Chunk_Flag :: enum { 
	None,
}
// Streaming object
Map_Chunk :: struct {
	id: Chunk_ID,
	bounds: Core.AABB,
	flags: Chunk_Flags,
	entity_count: u32,
	asset_dependency_offset: u32,
	asset_dependency_count: u32,
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
Entity_Flags :: bit_set[Entity_Flag]
Entity_Flag :: enum {
	None,
}

Chunk_Membership :: struct {
	chunk: Chunk_ID,
}

Scene :: struct {
	id: Core.Scene_ID,
	root: Entity,
}

World_Streaming :: struct {
	load_queue: queue.Queue(Chunk_ID),
	unload_queue: queue.Queue(Chunk_ID),
}