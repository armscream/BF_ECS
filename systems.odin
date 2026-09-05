// Engine/src/Modules/BF_ECS/systems.odin
//
// BF_ECS system declarations.
//
// Systems declare data access and execution stage.
// They do not declare threading policy.
//
// BF_DAG determines:
//     - dependency ordering
//     - parallelism
//     - worker assignment
//     - work stealing
//
// The callback receives Core.Scheduler_System_Context.
//
// worker_id is the worker that actually executed the system.

package BF_ECS

import "../../Core"
import "core:log"
import ode "/ode_ecs/src"

//* SYSTEM CONTEXT
ecs_system_world :: #force_inline proc(
	ctx: ^Core.Scheduler_System_Context,
) -> ^World {
	if ctx == nil || ctx.frame == nil do return nil
	return cast(^World)ctx.frame.world.ptr
}

ecs_system_frame :: #force_inline proc(
	ctx: ^Core.Scheduler_System_Context,
) -> ^Core.Scheduler_Frame {
	if ctx == nil do return nil
	return ctx.frame
}

ecs_system_dt :: #force_inline proc(
	ctx: ^Core.Scheduler_System_Context,
) -> f32 {
	if ctx == nil || ctx.frame == nil do return 0
	return ctx.frame.dt
}

ecs_system_frame_index :: #force_inline proc(
	ctx: ^Core.Scheduler_System_Context,
) -> u64 {
	if ctx == nil || ctx.frame == nil do return 0
	return ctx.frame.frame_index
}

ecs_system_worker_id :: #force_inline proc(
	ctx: ^Core.Scheduler_System_Context,
) -> int {
	if ctx == nil do return -1
	return ctx.worker_id
}

ecs_system_command_buffer :: #force_inline proc(
	ctx: ^Core.Scheduler_System_Context,
) -> ^ode.Command_Buffer {
	if ctx == nil || ctx.frame == nil do return nil
	world := cast(^World)ctx.frame.world.ptr
	if world == nil do return nil
	return world_command_buffer(world, ctx.worker_id)
}

//* SYSTEM REGISTRATION HELPERS
ECS_System_Description :: struct {
	name: string,
	execute: ECS_System_Proc,
	read_mask: Core.Access_Mask,
	write_mask: Core.Access_Mask,
	stage: Core.System_Stage,
}
ECS_System_Proc :: proc(rawptr)

ecs_register_system :: proc(
	api: ^Core.Component_Registration_API,
	ctx: ^Core.Lib_Context,
	description: ECS_System_Description,
) -> bool {
	if api == nil || ctx == nil do return false
	return api.add_system(
		ctx,
		Core.System_Registration{
			name = description.name,
			execute = description.execute,
			info = Core.System_Info{
				read_mask = description.read_mask,
				write_mask = description.write_mask,
				stage = description.stage,
			},
		},
	)
}

//* ACCESS MASK HELPERS
ecs_access_none :: #force_inline proc() -> Core.Access_Mask {
	return Core.access_mask_empty()
}
ecs_access_mask_from_bits :: #force_inline proc(bits: u64) -> Core.Access_Mask {
	return Core.access_mask_from_bits(bits)
}

//* BUILT IN SYSTEMS
ECS_SYSTEM_NAME_TICK :: "ECS.WorldTick"
ecs_system_world_tick :: proc(rawptr_ctx: rawptr){
	if rawptr_ctx == nil do return

	ctx := cast(^Core.Scheduler_System_Context)rawptr_ctx
	world := ecs_system_world(ctx)

	if world == nil do return

	world.tick += 1
	world.frame_idx = ecs_system_frame_index(ctx)

	when BF_ECS_LOG_TICK {
		log.infof(
			"[BF_ECS] tick=%d frame=%d dt=%.4f worker=%d",
			world.tick,
			world.frame_idx,
			ecs_system_dt(ctx),
			ecs_system_worker_id(ctx),
		)
	}
}

//* COMMAND BUFFER REPLAY
//* IMPORTANT:
// Replay is NOT registered as a normal DAG system.
//
// Command buffers are recorded concurrently by workers and must be replayed
// only after all recording systems have completed.
//
// Until BF_DAG has an explicit synchronization/barrier node, replay belongs
// to the engine's frame synchronization point, not the ordinary system DAG.
ecs_replay_command_buffers :: proc(
	world: ^World,
) {
	if world == nil do return

	for i in 0..<len(world.command_buffers) {
		ode.command_buffer__replay(
			&world.command_buffers[i],
		)
	}
}

//* BUILT-IN REGISTRATION
ecs_register_builtin_systems :: proc(
	api: ^Core.Component_Registration_API,
	ctx: ^Core.Lib_Context,
) -> bool {
	if api == nil || ctx == nil do return false

	tick := ECS_System_Description{
		name       = ECS_SYSTEM_NAME_TICK,
		execute    = ecs_system_world_tick,
		read_mask  = Core.access_mask_empty(),
		write_mask = Core.access_mask_empty(),
		stage      = .PreUpdate,
	}

	if !ecs_register_system(api, ctx, tick) {
		log.error("[BF_ECS] failed to register ECS.WorldTick")
		return false
	}

	return true
}

//* DEBUG
BF_ECS_LOG_TICK :: false