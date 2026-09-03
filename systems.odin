// Engine/src/Modules/BF_ECS/systems.odin
//
// Minimal BF_ECS system callbacks registered with the BF_DAG scheduler.
//
// Each callback receives a rawptr that points at a Core.Scheduler_Frame.
// Recovery pattern:
//
//     frame := cast(^Core.Scheduler_Frame)ctx
//     if frame == nil do return
//     world := cast(^World)frame.world.ptr
//     if world == nil do return
//
// We ship two systems today:
//
//   ECS.WorldTick       — increments world.tick + frame_index. This is the
//                         "is the DAG firing?" probe; it costs almost
//                         nothing and proves the dispatch loop works.
//   ECS.PartitionStale  — a stage-Update placeholder for the future
//                         partition/spatial-index update (plan §47-48).
//                         Today it is a no-op so the DAG has a second
//                         node and can demonstrate conflict detection.
package BF_ECS

import "core:log"
import "../../Core"

ECS_SYSTEM_NAME_TICK :: "ECS.WorldTick"
ECS_SYSTEM_NAME_PART  :: "ECS.PartitionStale"

// ============================================================================
// SYSTEM CALLBACKS
// ============================================================================

// ecs_system_world_tick runs once per frame. It increments the world's
// tick counter and copies the frame_index onto the world so application
// code can correlate scheduler ticks with ECS state.
ecs_system_world_tick :: proc(ctx: rawptr) {
	if ctx == nil do return
	frame := cast(^Core.Scheduler_Frame)ctx
	if frame == nil do return
	if frame.world.ptr == nil do return

	world := cast(^World)frame.world.ptr
	world.tick += 1
	world.frame_idx = frame.frame_index

	when BF_ECS_LOG_TICK {
		log.infof("[ECS] tick=%d frame=%d dt=%.4f", world.tick, world.frame_idx, frame.dt)
	}
}

// ecs_system_partition_stale is a no-op placeholder for the eventual
// world-partition/spatial-index update path. It exists today so the DAG
// has a second stage-Update system and so callers can stage their own
// work after it without needing access to BF_ECS internals.
ecs_system_partition_stale :: proc(ctx: rawptr) {
	_ = ctx
	// No-op for the minimum cut; full impl lands with the partition
	// update system described in plan §47 (Movement → Transform →
	// Hierarchy → Bounds → Partition → Spatial Index Rebuild).
}

// When true, ecs_system_world_tick logs every frame. Off by default
// because the per-frame log spams production runs; flip on for
// debugging the dispatcher.
BF_ECS_LOG_TICK :: false
