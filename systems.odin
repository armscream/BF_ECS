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

//* SYSTEM ACCESS
ecs_access_mask :: proc(component: Component_ID) -> Core.Access_Mask {
	id := u32(component)

	if id == u32(COMPONENT_INVALID) do return Core.access_mask_empty()

	// Core currently provides 64 access bits.
	// Component IDs are one-based.
	if id > 64 {
		when BF_ECS_LOG_SYSTEM_WARN {
			log.warnf(
				"[BF_ECS] component ID %d exceeds the current scheduler access mask",
				id,
			)
		}

		return Core.access_mask_empty()
	}

	return Core.Access_Mask{
		bits = u64(1) << u64(id - 1),
	}
}

ecs_access_mask_from_components :: proc(
	components: []Component_ID,
) -> Core.Access_Mask {
	mask := Core.access_mask_empty()

	for component in components {mask.bits |= ecs_access_mask(component).bits}

	return mask
}

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

//* BUILT-IN SYSTEMS
ECS_SYSTEM_NAME_TICK :: "ECS.WorldTick"

ecs_system_world_tick :: proc(rawptr_ctx: rawptr) {
	if rawptr_ctx == nil do return
	ctx := cast(^Core.Scheduler_System_Context)rawptr_ctx

	world := ecs_system_world(ctx)
	if world == nil do return 

	world.tick += 1
	world.frame_idx = ecs_system_frame_index(ctx)

	when BF_ECS_LOG_TICK {
		log.infof(
			"[ECS] tick=%d frame=%d dt=%.4f worker=%d",
			world.tick,
			world.frame_idx,
			ecs_system_dt(ctx),
			ecs_system_worker_id(ctx),
		)
	}
}

//* BUILT-IN REGISTRATION
ecs_register_builtin_systems :: proc(
	api: ^Core.Component_Registration_API,
	ctx: ^Core.Lib_Context,
) -> bool {
	if api == nil || ctx == nil do return false
	ok := api.add_system(
		ctx,
		Core.System_Registration{
			name    = ECS_SYSTEM_NAME_TICK,
			execute = ecs_system_world_tick,

			info = Core.System_Info{
				read_mask  = Core.access_mask_empty(),
				write_mask = Core.access_mask_empty(),
				stage      = .PreUpdate,
			},
		},
	)
	if !ok {
		log.error("[BF_ECS] failed to register ECS.WorldTick")
		return false
	}

	return true
}

//* DEBUG
BF_ECS_LOG_TICK :: false
BF_ECS_LOG_SYSTEM_WARN :: true