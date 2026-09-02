// Engine/src/Modules/BF_ECS/BF_ECS.odin
//
// Minimal BF_ECS module. Owners of every "is BF_ECS doing real work?"
// question eventually flow through here:
//
//   * register()   — allocate the World, register systems, register the
//                    World service so the application can find the
//                    ^World pointer.
//   * activate()   — log readiness; future code that needs engine-side
//                    settings (e.g. project_settings) can wire up here.
//   * deactivate() — currently a no-op.
//   * unload()     — destroy the World.
//
// The two systems registered here are defined in systems.odin:
//
//   ECS.WorldTick       — increments World.tick + World.frame_index.
//   ECS.PartitionStale  — no-op placeholder for the world-partition
//                         update stage (plan §47).
//
// Both run on the standard system callback ABI (`proc(ctx: rawptr)`),
// matching the rest of the engine. They read the World pointer from the
// module-local singleton `MODULE.world`, which is set during register().
// Once the application drives a frame loop via
// Core.engine_scheduler_get(), the DAG fires these systems each tick.
package BF_ECS

import "../../Core"
import "core:log"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Lib_Descriptor {
	api_version      = Core.LIB_API_VERSION,
	name             = "BF_ECS",
	version          = Core.Version{0, 0, 1},
	author           = "armscream",
	description      = "Minimal BF_ECS: entity storage, world partition, and DAG-registered ECS systems.",
	component_kind   = .Module,
	type             = .ECS,
	flags            = {.Runtime, .Provides_Service},
	capabilities     = {.ECS},
	dependencies     = {
		{
			name = "BF_DAG",
			min_version = Core.Version{0, 0, 1},
			max_version = Core.Version{9, 9, 9},
			has_max_version = true,
			has_min_version = true,
			optional = false,
		},
	},
	dependency_count = 1,
}
// === END MODULE_IDENTITY ===

MODULE_API := Core.LIB_API {
	descriptor = IDENTITY,
	load       = module_load,
	register   = module_register,
	activate   = module_activate,
	deactivate = module_deactivate,
	unload     = module_unload,
}

when #config(BUILDING_BF_ECS_DLL, false) {
	@(export)
	bifrost_lib_get_api :: proc() -> ^Core.LIB_API {
		return &MODULE_API
	}
}

// ============================================================================
// MODULE STATE
// ============================================================================

// Singleton ECS state. Lives for the lifetime of the BF_ECS module;
// systems read the World pointer from here. Exposed through a service
// of the same name so application code can reach it without going
// through the BF_ECS package symbol set.
MODULE_STATE :: struct {
	world: ^World,
}
@(private)
MODULE_STATE_VALUE.world = world_create(context.allocator)

// Convenience: systems read this; module loaders also clear/nil it.
module_world :: proc() -> ^World {
	return MODULE_STATE_VALUE.world
}

// ============================================================================
// LIFECYCLE
// ============================================================================

module_load :: proc(ctx: ^Core.Lib_Context) -> bool {
	_ = ctx
	log.info("[BF_ECS] loaded")
	return true
}

module_register :: proc(ctx: ^Core.Lib_Context) -> bool {
	// *Allocate the World.
	MODULE_STATE_VALUE.world = world_create(context.allocator)
	if MODULE_STATE_VALUE.world == nil {
		log.error("[BF_ECS] failed to allocate World")
		return false
	}

	// Look up the registration API so we can declare systems + the
	// World service before the component manager promotes us.
	api_raw := Core.lib_context_query(
		ctx,
		Core.CORE_LIB_INTERFACE_COMPONENT_REGISTRATION,
		Core.COMPONENT_REGISTRATION_API_VERSION,
	)
	if api_raw == nil {
		log.error("[BF_ECS] component_registration interface unavailable")
		return false
	}
	api := cast(^Core.Component_Registration_API)api_raw


	// *Register the systems that participate in the DAG.
	// Each system is a proc(rawptr) callback. The DAG compiles
	// dependencies from System_Info masks/stage; for the minimum
	// cut both systems sit at stage = .Update with empty masks,
	// which the engine maps to default `.Update` Stage info.

	tick_reg := Core.System_Registration {
		name = BF_ECS_SYSTEM_NAME_TICK,
		execute = ecs_system_world_tick,
		info = Core.System_Info{stage = .Update},
	}
	if !api.add_system(ctx, tick_reg) {
		log.error("[BF_ECS] failed to register %s", ECS_SYSTEM_NAME_TICK)
		world_destroy(MODULE_STATE_VALUE.world)
		MODULE_STATE_VALUE.world = nil
		return false
	}

	part_reg := Core.System_Registration {
		name = ECS_SYSTEM_NAME_PART,
		execute = ecs_system_partition_stale,
		info = Core.System_Info{stage = .Update},
	}
	if !api.add_system(ctx, part_reg) {
		log.error("[ECS] failed to register %s", ECS_SYSTEM_NAME_PART)
		world_destroy(MODULE_STATE_VALUE.world)
		MODULE_STATE_VALUE.world = nil
		return false
	}

	// *Register a service so application code can reach the World.
	// The Core service registry will call ecs_world_destroy when the
	// module unloads — that frees the World as part of normal teardown.
	sreg := Core.Service_Registration {
		name     = ECS_WORLD_SERVICE_NAME,
		instance = cast(rawptr)MODULE_STATE_VALUE.world,
		destroy  = ecs_world_destroy,
	}
	if !api.add_service(ctx, sreg) {
		log.error("[ECS] failed to register world service")
		world_destroy(MODULE_STATE_VALUE.world)
		MODULE_STATE_VALUE.world = nil
		return false
	}

	log.infof("[BF_ECS] registered %d systems (tick + partition-stale) and world service.", 2)
	return true
}

module_activate :: proc(ctx: ^Core.Lib_Context) -> bool {
	_ = ctx
	log.infof("[BF_ECS] activated — world=%p", MODULE_STATE_VALUE.world)
	return MODULE_STATE_VALUE.world != nil
}

module_deactivate :: proc(ctx: ^Core.Lib_Context) {
	_ = ctx
}

module_unload :: proc(ctx: ^Core.Lib_Context) {
	_ = ctx
	// World destruction is owned by the Core service registry's destroy
	// callback (see ecs_world_destroy). The MODULE_STATE_VALUE.world
	// pointer is invalidated there. Nothing else to free here.
	log.info("[BF_ECS] unloaded")
}

// ============================================================================
//* SERVICE
// ============================================================================

// Service name used by application code and the engine to find the
// BF_ECS World pointer. Kept stable; renaming it is an API break.
ECS_WORLD_SERVICE_NAME :: "BF_ECS.World"

// ecs_world_destroy is the Core service-registry destroy callback for
// the BF_ECS World. It tears the World down and nils the singleton so
// any subsequent system invocation sees a nil world and short-circuits
// instead of dereferencing freed memory.
ecs_world_destroy :: proc(instance: rawptr) {
	if instance == nil do return
	world := cast(^World)instance
	world_destroy(world)
	if MODULE_STATE_VALUE.world == world {
		MODULE_STATE_VALUE.world = nil
	}
}