package BF_ECS

import "../../Core"
import mth "../../Core/BF_Math"

//* ASSETS
Asset_ID :: Core.Asset_ID
Asset_Ref :: Core.Asset_Ref

//* TRANSFORM

Transform_Local :: struct {
	position: mth.Vec3,
	rotation: quaternion128,
	scale:    mth.Vec3,
}

Transform :: struct {
	local:          Transform_Local,
	world:          mth.Mat4,
	previous_world: mth.Mat4,
	dirty:          bool,
}

//* RENDERING

Render_Model :: struct {
	model: Asset_Ref,
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

Render_Material_Override :: struct {
	slot:     u16,
	material: Asset_Ref,
}

//* SPATIAL

Chunk_ID :: distinct u64

CHUNK_INVALID :: Chunk_ID(0)

Chunk_Membership :: struct {
	chunk: Chunk_ID,
}

Spatial_Bounds :: struct {
	local: mth.AABB,
	world: mth.AABB,
}

Spatial_State :: struct {
	flags: Spatial_Flags,
}

Spatial_Flags :: bit_set[Spatial_Flag]

Spatial_Flag :: enum u8 {
	Loaded,
	Active,
	Visible,
	Simulated,
	Replicated,
	Navigable,
}

//* CAMERA

Camera_Projection :: enum u8 {
	Perspective,
	Orthographic,
}

Camera :: struct {
	projection:   Camera_Projection,
	fov_y:        f32,
	aspect:       f32,
	near_plane:   f32,
	far_plane:    f32,
	ortho_height: f32,
	exposure:     f32,
}

// Tag component marking the entity whose camera the renderer should treat
// as the currently active one. There is at most one entity with this
// component per world; see BF_GPU.Extraction for the active-camera
// selection rules.
Camera_Active :: struct {
	value: bool,
}

//* LIGHTING

Light_Type :: enum u8 {
	Directional,
	Point,
	Spot,
	Area,
}

Light :: struct {
	type:         Light_Type,
	color:        mth.Vec3,
	intensity:    f32,
	range:        f32,
	inner_cone:   f32,
	outer_cone:   f32,
	size:         mth.Vec2,
	casts_shadow: bool,
}

Light_Shadow :: struct {
	enabled:     bool,
	bias:        f32,
	normal_bias: f32,
	resolution:  u32,
}

//* PARTICLES

Particle_Emitter :: struct {
	system:        Asset_Ref,
	seed:          u64,
	enabled:       bool,
	rate:          f32,
	lifetime:      f32,
	max_particles: u32,
}

//* PHYSICS

Physics_Body :: struct {
	body_id: u32,
}

Physics_Collider :: struct {
	shape: Asset_Ref,
	layer: u64,
	mask:  u64,
}

Physics_State :: struct {
	active: bool,
}

//* REPLICATION

Replication_Mode :: enum u8 {
	Never,
	Always,
	Owner,
	OnChange,
	Continuous,
}

Replication :: struct {
	mode:     Replication_Mode,
	owner:    Entity,
	priority: u8,
	flags:    Replication_Flags,
}

Replication_Flags :: bit_set[Replication_Flag]

Replication_Flag :: enum u8 {
	Spawn,
	Destroy,
	Transform,
	Reliable,
}
