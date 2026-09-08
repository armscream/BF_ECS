// BF_ECS/Spatial.odin
package BF_ECS

import "../../Core"
import ode "/ode_ecs/src"
import hm "core:container/handle_map"
import "core:container/queue"

Map_ID :: distinct u64
Chunk_ID :: distinct u64
CHUNK_INVALID :: Chunk_ID(0)
Chunk_Membership :: struct {
	chunk_id: Chunk_ID,
}

Chunk_Store :: struct {
	chunks: [dynamic]Map_Chunk,
	by_id:  [dynamic]Chunk_ID,
}

Spatial_Flags :: bit_set[Spatial_Flag]
Spatial_Flag :: enum {
	Loaded,
	Active,
	Renderable,
	Simulated,
	Replicated,
	Navigable,
}
Spatial_State :: struct {
	flags: Spatial_Flags,
}

// Streaming object
Map_Chunk :: struct {
	id:                      Chunk_ID,
	bounds:                  Core.AABB,
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
	world_bounds: Core.AABB,
	chunk_size:   f32,
	chunk_count:  u32,
	entity_count: u32,
	flags:        Map_Flags,
}

Map_Flags :: bit_set[Map_Flag]
Map_Flag :: enum {} // empty for now


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

//* Renderables
Render_Model :: struct {
	model: Core.Asset_Ref,
	flags: Render_Instance_Flags,
}
Render_Instance_Flags :: bit_set[Render_Instance_Flag]
Render_Instance_Flag :: enum u8 {
	Visible,
	Cast_Shadow,
	Receive_Shadow,
	Static,
	Dynamic,
	Hidden,
}

Material_Override :: struct {
	slot: u16,
	material: Core.Asset_Ref,
}

Render_Material_Overrides :: struct {
	slot: u16,
	material: Core.Asset_Ref,
}
// CAMERA
Camera_Projection :: enum u8 {
	Perspective,
	Orthographic,
}
Camera :: struct { 
	projection: Camera_Projection,
	fov_y: f32,
	aspect_ratio: f32,
	near_plane: f32,
	far_plane: f32,
	ortho_height: f32,
	exposure: f32,
}
Camera_Active :: struct {
	value: bool,
}

// LIGHT
Light_Type :: enum u8 {
	Directional,
	Point,
	Spot,
	Area,
}
Light :: struct { 
	type: Light_Type,
	color: vec3,
	intensity: f32,
	range: f32,
	inner_cone: f32,
	outer_cone: f32,
	size: mth.Vec2,
	cast_shadow: bool,
}
Light_Shadow :: struct {
	enabled: bool,
	bias: f32,
	normal_bias: f32,
	resolution: u32,
}

// PARTICLE Component
Particle_Emitter :: struct {
	system: Core.Asset_Ref,
	seed: u64,
	enabled: bool,
	rate: f32,
	lifetime: f32,
	max_particles: u32,
}

// Physics Component
Physics_Body :: struct { 
	body_id: u32,
}
Physics_Collider :: struct { 
	shape: Asset_Ref,
	layer: u64,
	mask: u64,
}
Physics_State :: struct {
	active: bool,
}

// Replication
Replication_Mode :: enum u8 {
	Never,
	Always,
	Owner,
	Onchange,
	Continuous,
}
Replication :: struct {
	mode: Replication_Mode,
	owner: Entity,
	priority: u8,
	flags: Replication_Flags,
}
Replication_Flags :: bit_set[Replication_Flag]
Replication_Flag :: enum u8 { 
	Spawn,
	Destroy,
	Transform,
	Reliable,
}