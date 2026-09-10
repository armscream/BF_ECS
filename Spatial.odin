// BF_ECS/Spatial.odin
package BF_ECS

import "../../Core"
import ode "/ode_ecs/src"
import mth "../../Core/BF_Math"
import "core:container/queue"

// Streaming object
Map_Chunk :: struct {
	id:                      Chunk_ID,
	bounds:                  mth.AABB,
	flags:                   Chunk_Flags,
	entity_count:            u32,
	asset_dependency_offset: u32,
	asset_dependency_count:  u32,
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
	world_bounds: mth.AABB,
	chunk_size:   f32,
	chunk_count:  u32,
	entity_count: u32,
	flags:        Map_Flags,
}

Map_Entity_Record :: struct {
	id:               Entity,
	chunk:            Chunk_ID,
	flags:            Entity_Flags,
	archetype:        ode.Arch_Table, 
	component_offset: u32,
}
Entity_Flags :: bit_set[Entity_Flag]
Entity_Flag :: enum {
	None,
}

World_Streaming :: struct {
	load_queue:   queue.Queue(Chunk_ID),
	unload_queue: queue.Queue(Chunk_ID),
}

Scene_ID :: distinct u64
SCENE_INVALID :: Scene_ID(0)

Scene :: struct {
	id:    Scene_ID,
	name:  string,
	root:  Entity,
	flags: Scene_Flags,
}
Scene_Flags :: bit_set[Scene_Flag]
Scene_Flag :: enum u8 {
	Persistent,
	Streamable,
	Editor_Only,
	Runtime,
}


Material_Override :: struct {
	slot: u16,
	material: Core.Asset_Ref,
}

Render_Material_Overrides :: struct {
	slot: u16,
	material: Core.Asset_Ref,
}

Camera_Active :: struct {
	value: bool,
}