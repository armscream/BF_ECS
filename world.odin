// Engine/src/Modules/BF_ECS/world.odin
//
// Minimal World state. The plan describes a deeply layered ECS (archetypes,
// sparse sets, relationships, hierarchy, world partition, spatial index).
// For the first cut the only things the DAG actually need to reach from a
// system callback are:
//
//   * a tick counter (so a system callback can prove the DAG fired)
//   * a slot for the World_Spatial partition (so a future "partition
//     update" system has somewhere to read/write state)
//
// Everything else will fill in over time. We deliberately keep this file
// small so the DAG can be exercised end-to-end without taking on every
// piece of plan.md at once.
package BF_ECS

import "core:mem"
import "../../Core"

// World is the per-application ECS state. The engine holds an opaque
// ^World in Core.World_Handle.ptr; system callbacks recover it via:
//
//     frame := cast(^Core.Scheduler_Frame)ctx
//     world := cast(^World)frame.world.ptr
//
// and read/write from there. The state stored here is intentionally
// minimal — full archetype/sparse-set storage is the next phase.
World :: struct {
	tick:        u64,
	frame_index: u64,
	allocator:   mem.Allocator,
	spatial:     World_Spatial,
}

// world_create allocates a World with default settings read from the
// engine's project settings. Returns nil on allocator failure.
world_create :: proc(allocator: mem.Allocator = context.allocator) -> ^World {
	w := new(World, allocator)
	w.allocator = allocator

	// Default the spatial partition to whatever the project defines.
	// project_settings is exposed by Core.lib_context_query at module
	// activate time; for now we use Core's DEFAULT_SPATIAL_SETTINGS so
	// the partition is constructible without a settings handshake.
	settings := Core.DEFAULT_SPATIAL_SETTINGS

	if !world_spatial_init(&w.spatial, settings, allocator) {
		free(w, allocator)
		return nil
	}

	return w
}

// world_destroy tears down the partition then frees the World itself.
// Pair with world_create.
world_destroy :: proc(world: ^World) {
	if world == nil do return
	world_spatial_destroy(&world.spatial)
	free(world, world.allocator)
}
