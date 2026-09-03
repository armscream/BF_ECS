// Engine/src/Modules/BF_ECS/systems.odin
//
// BF_ECS system registration and execution context.
//
// BF_ECS systems are registered with Core's scheduler ABI. BF_DAG owns
// execution, dependency analysis, worker assignment, and work stealing.
//
// A system callback receives a Core.Scheduler_System_Context. The context
// contains:
//     * the current frame
//     * the World
//     * the worker that is ACTUALLY executing the system
//     * that worker's command buffer
//
// The worker ID is execution-time state, not compile-time ownership state.
// This is important because BF_DAG permits work stealing.
//
// Command buffers are therefore:
//
//     World.command_buffers[worker_id]
//
// and are never shared between workers during a frame.
package BF_ECS

import "../../Core"
import "core:log"

//* SYSTEM FLAGS
// These flags describe properties of an ECS system.
// TODO: Decide if necessary. DAG can handle a lot of things automatically, like worker affinity.
// The scheduler currently uses read/write masks for conflict detection.
// These flags are BF_ECS metadata and allow us to expand the execution model
// without changing the basic callback ABI.
ECS_System_Flag :: enum u32 {
	None,
	// System may record structural changes into its worker command buffer.
	Structural,
	// System may execute in parallel with systems that have compatible component access.
	Parallel,
	// System does not access ECS component storage.
	// Useful for pure engine/frame systems.
	No_ECS_Access,
	// System requires the main worker.
	Main_Thread,
	// System may execute on any worker, including a stolen worker.
	Worker_Any,
	// System must remain on its compiled/preferred worker.
	Worker_Pinned,
}
ECS_System_Flags :: bit_set[ECS_System_Flag]

//* ECS SYSTEM CONTEXT
// the scheduler is responsible for filling this context before invoking the system callback.
//* IMPORTANT:
// The context itself is execution-local. It must NOT be stored by a system.
ECS_System_Context :: struct {
	frame:     ^Core.Scheduler_Frame,
	world:     ^World,
	worker_id: int,
	commands:  ^Command_Buffer,
}

//* SYSTEM CALLBACK
ECS_System_Proc :: proc(ctx: ^Core.Scheduler_System_Context)

//* SYSTEM DESCRIPTION
// This is the BF_ECS-side description used by registration helpers.
//
// Core.System_Registration remains the ABI boundary.
//
// `read_mask` and `write_mask` are still Core.Access_Mask because that is
// what BF_DAG currently consumes for dependency compilation.
//
// Later, once BF_DAG/Core support more than 64 access bits, these helpers can
// be extended without changing ECS system declarations.
ECS_System_Description :: struct {
	name:       string,
	stage:      Core.System_Stage,
	read_mask:  Core.Access_Mask,
	write_mask: Core.Access_Mask,
	flags:      ECS_System_Flags,
	execute:    ECS_System_Proc,
}

//* ACCESS MASK HELPERS
// Component IDs are BF_ECS IDs, so component 1 maps to bit 0, component 2 to
// bit 1, etc.
//
// Component ID 0 is invalid.
//
// We deliberately reject IDs >= 64 rather than silently wrapping them.
//
// This is temporary until the scheduler's access-mask representation is
// expanded to cover ODE_ECS's larger component space.
ecs_access_mask :: proc(component: Component_ID) -> Core.Access_Mask {
	id := u32(component)
	if id == u32(COMPONENT_INVALID) do return Core.access_mask_empty()
	if id >= 64 { 	// TODO: Reject IDs >= 64, until DAG supports larger masks.
		when BF_ECS_LOG_SYSTEM_WARN {
			log.warnf(
				"[BF_ECS] component ID %d cannot be represented by the current 64-bit scheduler access mask",
				id,
			)
		}
		return Core.access_mask_empty()
	}
	return Core.Access_Mask{bits = u64(1) << u64(id - 1)}
}
ecs_access_mask_from_components :: proc(components: []Component_ID) -> Core.Access_Mask {
	mask := Core.access_mask_empty()
	for component in components {
		part := ecs_access_mask(component)
		mask.bits |= part.bits
	}
	return mask
}

//* SYSTEM REGISTRATION
// Converts BF_ECS metadata into Core.System_Registration.
//
// Core collects these registrations from every loaded component and later
// passes the resulting System_Entry array to BF_DAG.
//
// BF_DAG then builds:
//     stage dependencies
//     read/write conflicts
//     explicit dependencies
//     worker affinity
//     cache groups
//     execution DAG
ecs_system_registration :: proc(description: ECS_System_Description) -> Core.System_Registration {
	return Core.System_Registration {
		name = description.name,
		execute = ecs_system_dispatch,
		info = Core.System_Info {
			read_mask = description.read_mask,
			write_mask = description.write_mask,
			stage = description.stage,
			flags = u32(description.flags),
		},
	}
}

//* SYSTEM DISPATCH
// Core/BF_DAG currently invokes proc(rawptr).
//
// BF_DAG will pass a pointer to Core.Scheduler_System_Context.
//
// The adapter validates the context and resolves the BF_ECS World.
//
// We keep this adapter separate from the actual system callback so all ECS
// systems get identical execution semantics.
ecs_system_dispatch :: proc(rawptr_ctx: rawptr) {
	if rawptr_ctx == nil do return
	sched_ctx := cast(^Core.Scheduler_System_Context)rawptr_ctx
	if sched_ctx == nil || sched_ctx.frame == nil do return
	frame := sched_ctx.frame
	if frame.world.ptr == nil do return
	world := cast(^World)frame.world.ptr
	if world == nil do return

	ctx := ECS_System_Context {
		frame     = frame,
		world     = world,
		worker_id = sched_ctx.worker_id,
		commands  = world_command_buffer_for_worker(world, sched_ctx.worker_id),
	}
	// The actual system-specific callback is still task.fn.
	//
	// Therefore this wrapper cannot itself know which ECS callback to call.
}

//* INTERNAL CALLBACK ABI
// Core's System_Entry currently stores only proc(rawptr), so the BF_ECS
// callback has to be carried through the scheduler context.
//
// This helper is used by module registration below.
ecs_system_dispatch_callback :: proc(rawptr_ctx: rawptr, callback: ECS_System_Proc) {
	if rawptr_ctx == nil || callback == nil do return
	sched_ctx := cast(^Core.Scheduler_System_Context)rawptr_ctx
	if sched_ctx == nil do return
	frame := sched_ctx.frame
	if frame == nil || frame.world.ptr == nil do return
	world := cast(^World)frame.world.ptr
	if world == nil do return
	ctx := ECS_System_Context {
		frame     = frame,
		world     = world,
		worker_id = sched_ctx.worker_id,
		commands  = world_command_buffer_for_worker(world, sched_ctx.worker_id),
	}
	callback(&ctx)
}

//* SYSTEM REGISTRATION WITH CALLBACK
// This is the function BF_ECS modules should use.
//
// Example:
//     ecs_register_system(
//         api,
//         ctx,
//         ECS_System_Description{
//             name       = "Transform.Update",
//             stage      = .Update,
//             read_mask  = ...,
//             write_mask = ...,
//             flags      = {.Parallel},
//             execute    = transform_update,
//         },
//     )
//
// The Core registration API still stores a proc(rawptr), so the callback
// association is handled through the system registry implementation.
//
// See the note below about the current Core ABI.
ecs_register_system :: proc(
	api: ^Core.Component_Registration_API,
	ctx: ^Core.Lib_Context,
	description: ECS_System_Description,
) -> bool {
	if api == nil || ctx == nil do return false
	if description.execute == nil do return false
	registration := Core.System_Registration {
		name = description.name,
		execute = proc(rawptr_ctx: rawptr) {
			if rawptr_ctx == nil do return
			if sched_ctx == nil do return
			frame := sched_ctx.frame
			if frame == nil || frame.world.ptr == nil do return
			world := cast(^World)frame.world.ptr
			if world == nil do return
			system_ctx := ECS_System_Context {
				frame     = frame,
				world     = world,
				worker_id = sched_ctx.worker_id,
				commands  = world_command_buffer_for_worker(world, sched_ctx.worker_id),
			}
			description.execute(&system_ctx)
		},
		info = Core.System_Info {
			read_mask = description.read_mask,
			write_mask = description.write_mask,
			stage = description.stage,
			flags = u32(description.flags),
		},
	}
	return api.add_system(ctx, registration)
}

//* COMMAND BUFFER ACCESS
// The command buffer is selected from the ACTUAL worker.
// This is deliberately not based on Frame_DAG.owner_worker.
// A node can be stolen by another worker.
world_command_buffer_for_worker :: proc(world: ^World, worker_id: int) -> ^Command_Buffer {
	if world == nil || worker_id < 0 do return nil
	if worker_id >= len(world.command_buffers) {
		when BF_ECS_LOG_SYSTEM_WARN {
			log.warnf(
				"[BF_ECS] worker %d has no command buffer (capacity %d)",
				worker_id,
				len(world.command_buffers),
			)
		}
		return nil
	}
	return &world.command_buffers[worker_id]
}

//* SYSTEM CONTEXT HELPERS
system_dt :: #force_inline proc(ctx: ^ECS_System_Context) -> f32 {
	if ctx == nil || ctx.frame == nil do return 0
	return ctx.frame.dt
}
system_frame_index :: #force_inline proc(ctx: ^ECS_System_Context) -> u64 {
	if ctx == nil || ctx.frame == nil do return 0
	return ctx.frame.frame_index
}
system_worker_id :: #force_inline proc(ctx: ^ECS_System_Context) -> int {
	if ctx == nil do return -1
	return ctx.worker_id
}
system_world :: #force_inline proc(ctx: ^ECS_System_Context) -> ^World {
	if ctx == nil do return nil
	return ctx.world
}
system_commands :: #force_inline proc(ctx: ^ECS_System_Context) -> ^Command_Buffer {
	if ctx == nil do return nil
	return ctx.commands
}
ecs_system_world :: #force_inline proc(ctx: ^Core.Scheduler_System_Context) -> ^World {
	if ctx == nil || ctx.frame == nil do return nil 
	return cast(^World)ctx.frame.world.ptr
}
ecs_system_commands :: #force_inline proc(ctx: ^Core.Scheduler_System_Context)->^Command_Buffer {
	world := ecs_system_world(ctx)
	if world == nil do return nil
	return world_command_buffer_for_worker(world, ctx.worker_id)
}

//* BUILT-IN ECS SYSTEMS
// These are intentionally tiny.
// WorldTick is not an ECS data-processing system. It exists to establish
// the BF_ECS frame boundary.
// CommandReplay is the structural synchronization point.
//
//* IMPORTANT:
// CommandReplay must execute after all systems that can record structural
// commands in the relevant stage.
//
// For the initial implementation it lives in PostUpdate.
ecs_system_world_tick :: proc(ctx: ^ECS_System_Context) {
	if ctx == nil || ctx.world == nil do return
	ctx.world.tick += 1
	ctx.world.frame_idx = system_frame_index(ctx)
	when BF_ECS_LOG_TICK {
		log.infof(
			"[ECS] tick=%d frame=%d dt=%.4f",
			ctx.world.tick,
			ctx.world.frame_idx,
			system_dt(ctx),
		)
	}
}

//* COMMAND BUFFER REPLAY
// All worker command buffers are replayed here.
//
// This system must not run concurrently with systems that are still recording commands.
//
// The DAG stage ordering guarantees that all earlier Update systems have
// completed before this PostUpdate system executes.
ecs_system_replay_commands :: proc(ctx: ^ECS_System_Context) {
	if ctx == nil || ctx.world == nil do return
	world := ctx.world
	for buffer in world.command_buffers {
		if buffer == nil do continue
		if !command_buffer_is_valid(buffer) do continue
		_, ok := command_buffer_replay(buffer)
		if !ok {
			when BF_ECS_LOG_SYSTEM_WARN {
				log.warnf{"[BF_ECS] Failed to replay command buffer '%s'", buffer.name}
			}
		}
	}
}

//* BUILT-IN SYSTEM REGISTRATIONS
// TODO: Add more built-in systems when necessary
ecs_register_builtin_systems :: proc(
	api: ^Core.Component_Registration_API,
	ctx: ^Core.Lib_Context,
) -> bool {
	if api == nil || ctx == nil do return false
	//* WORLD TICK
	tick_ok := ecs_register_system(
		api,
		ctx,
		ECS_System_Description {
			name = ECS_SYSTEM_NAME_TICK,
			stage = .PreUpdate,
			read_mask = Core.access_mask_empty(),
			write_mask = Core.access_mask_empty(),
			flags = {.No_ECS_Access, .Worker_Any},
			execute = ecs_system_world_tick,
		},
	)
	if !tick_ok {
		log.error("[BF_ECS] Failed to register world tick system.")
		return false
	}

	//* Structural command replay
	replay_ok := ecs_register_system(
		api,
		ctx,
		ECS_System_Description {
			name = ECS_SYSTEM_NAME_COMMAND_REPLAY,
			stage = .PostRender,
			read_mask = Core.access_mask_empty(),
			write_mask = Core.access_mask_empty(),
			flags = {.No_ECS_Access, .Main_Thread},
			execute = ecs_system_replay_commands,
		},
	)
	if !replay_ok {
		log.error("[BF_ECS] Failed to register command replay system.")
		return false
	}
	return true
}

//* NAMES
ECS_SYSTEM_NAME_TICK :: "ECS.WorldTick"
ECS_SYSTEM_NAME_COMMAND_REPLAY :: "ECS.CommandReplay"

//* DEBUG OPTIONS
BF_ECS_LOG_TICK :: false
BF_ECS_LOG_SYSTEM_WARN :: true
