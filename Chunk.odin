// Engine/src/Modules/BF_ECS/Chunk.odin
//
// BF_ECS runtime chunk index.
//
// Chunks are world-space spatial/streaming units. They are NOT:
//   - ECS archetypes / table chunks
//   - renderer scenes
//   - GPU allocations
//
// The chunk index is the runtime accelerator over the persistent
// `Chunk_Membership` component on the Spatial database. It owns:
//   - the per-chunk runtime state (Unloaded..Unloading)
//   - dense, per-chunk entity lists
//   - a fast entity -> chunk reverse lookup
//
// Cross-boundary membership changes are funnelled through this module so
// the runtime index and the Chunk_Membership component stay in sync.

package BF_ECS

import mth "../../Core/BF_Math"
import "base:runtime"
import "core:math"

//* CHUNK FLAGS
// Persistent flags carried by a chunk entry (`.Persistent`, `.Streamable`,
// `.Baked`, ...). These are static metadata describing what a chunk *is*,
// not its runtime lifecycle — see `Chunk_Runtime_State` and `Chunk_States`
// for the per-frame / per-subsystem bits.
Chunk_Flags :: bit_set[Chunk_Flag]
Chunk_Flag :: enum {
	Persistent,
	Streamable,
	Loaded,
	Visible,
	Simulated,
	Replicated,
	Baked,
}

//* MAP FLAGS
// Persistent flags carried by a serialized map document (`.Persistent`,
// `.Streamable`, `.Editor`, `.Runtime`). BF_MapDB writes the bitset into
// the BMAP metadata section; BF_MapDB consumers use them to decide whether
// the document is editor-only, runtime-loadable, etc.
Map_Flags :: bit_set[Map_Flag]
Map_Flag :: enum u8 {
	Streaming,
	Persistent,
	Editor,
	Runtime,
}

//* CHUNK RUNTIME STATE
// Streaming lifecycle of a chunk. Independent from the per-subsystem
// `Chunk_State` bits: the lifecycle describes whether the chunk is
// physically present, while the bits describe whether it participates
// in each subsystem (renderer / gameplay / server replication / ...).
Chunk_Runtime_State :: enum u8 {
	Unloaded,
	Loading,
	Loaded,
	Activating,
	Active,
	Unloading,
}

//* CHUNK SEMANTIC STATE BITS
// Orthogonal flags describing whether a chunk is currently participating
// in each engine subsystem. Each subsystem (renderer extraction, server
// replication, AI / navigation, gameplay simulation) derives its own
// relevant set from these flags. These are intentionally not a single
// "visibility" or "replication" state — see prompt_plan §16:
//   "Do not make chunk state a universal visibility/replication system;
//    each subsystem should derive its own relevant set."
Chunk_State :: enum u8 {
	Loaded,      // chunk assets / entities are resident
	Active,      // participates in regular simulation
	Visible,     // contributes to renderer extraction
	Simulated,   // gameplay systems tick entities in this chunk
	Replicated,  // server replicates chunk to interested clients
	Navigable,   // AI / navigation can pathfind through this chunk
}
Chunk_States :: bit_set[Chunk_State]

//* CHUNK RUNTIME
// Per-chunk CPU-side state. Updated as chunks stream in / out.
Chunk_Runtime :: struct {
	id:             Chunk_ID,
	state:          Chunk_Runtime_State,
	states:         Chunk_States,
	bounds:         mth.AABB,
	flags:          Chunk_Flags,
	entity_count:   u32,
	loaded_tick:    u64,
	last_used_tick: u64,
}

//* CHUNK INDEX SETTINGS
Chunk_Index_Settings :: struct {
	// World-space size of one chunk edge. The chunk grid is uniform and
	// axis-aligned; chunk coordinates derive from world position via
	// floor(pos / chunk_size). 0 disables the grid helper.
	chunk_size:      f32,
	// Initial dense-array capacity for runtimes and per-chunk entity lists.
	initial_capacity: int,
}

CHUNK_INDEX_DEFAULT_SETTINGS :: Chunk_Index_Settings {
	chunk_size       = 64.0,
	initial_capacity = 256,
}

//* CHUNK INDEX
Chunk_Index :: struct {
	allocator: runtime.Allocator,
	settings:  Chunk_Index_Settings,
	// Dense runtimes, parallel to chunk_entities.
	runtimes:       [dynamic]Chunk_Runtime,
	// Chunk_ID -> dense index into `runtimes` / `chunk_entities`.
	runtime_by_id:  map[Chunk_ID]int,
	// Per-chunk entity lists, parallel to `runtimes`.
	chunk_entities: [dynamic][dynamic]Entity,
	// Entity -> dense index into `chunk_entities` (NOT Chunk_ID).
	entity_chunk:   map[Entity]int,
}

//* INITIALIZATION
chunk_index_init :: proc(
	index: ^Chunk_Index,
	settings: Chunk_Index_Settings = CHUNK_INDEX_DEFAULT_SETTINGS,
	allocator: runtime.Allocator = context.allocator,
) -> bool {
	if index == nil do return false
	if index.allocator.procedure != nil do return false
	if settings.initial_capacity < 0 do return false
	if settings.chunk_size < 0 do return false

	index.allocator = allocator
	index.settings = settings
	index.runtimes = make([dynamic]Chunk_Runtime, 0, settings.initial_capacity, allocator)
	index.runtime_by_id = make(map[Chunk_ID]int, allocator)
	index.chunk_entities = make([dynamic][dynamic]Entity, 0, settings.initial_capacity, allocator)
	index.entity_chunk = make(map[Entity]int, allocator)
	return true
}

//* DESTRUCTION
chunk_index_destroy :: proc(index: ^Chunk_Index) {
	if index == nil do return
	if index.allocator.procedure == nil do return
	for &list in index.chunk_entities {
		delete(list)
	}
	delete(index.chunk_entities)
	delete(index.runtimes)
	delete(index.runtime_by_id)
	delete(index.entity_chunk)
	index^ = {}
}

//* VALIDATION
chunk_index_is_valid :: #force_inline proc(index: ^Chunk_Index) -> bool {
	if index == nil do return false
	return index.allocator.procedure != nil
}

//* REGISTER
// Declare a chunk at runtime. Returns the dense runtime pointer (stable
// for the lifetime of the index) or nil on failure (invalid id, duplicate).
chunk_index_register :: proc(
	index: ^Chunk_Index,
	id: Chunk_ID,
	bounds: mth.AABB,
	flags: Chunk_Flags = {},
) -> ^Chunk_Runtime {
	if !chunk_index_is_valid(index) do return nil
	if id == CHUNK_INVALID do return nil
	if id in index.runtime_by_id do return nil

	dense := len(index.runtimes)
	append(&index.runtimes, Chunk_Runtime {
		id             = id,
		state          = .Unloaded,
		states         = {},
		bounds         = bounds,
		flags          = flags,
		entity_count   = 0,
		loaded_tick    = 0,
		last_used_tick = 0,
	})
	list := make([dynamic]Entity, 0, 16, index.allocator)
	append(&index.chunk_entities, list)
	index.runtime_by_id[id] = dense
	return &index.runtimes[dense]
}

//* UNREGISTER
// Removes a chunk from the index. Any entities currently membered to it
// have their entity_chunk entry cleared (callers are expected to also
// clear / replace the Chunk_Membership component).
chunk_index_unregister :: proc(index: ^Chunk_Index, id: Chunk_ID) -> bool {
	if !chunk_index_is_valid(index) do return false
	dense, ok := index.runtime_by_id[id]
	if !ok do return false

	list := index.chunk_entities[dense]
	for entity in list {
		delete_key(&index.entity_chunk, entity)
	}
	delete(list)

	// swap-remove from dense arrays to keep them packed
	last := len(index.runtimes) - 1
	if dense != last {
		index.runtimes[dense] = index.runtimes[last]
		index.chunk_entities[dense] = index.chunk_entities[last]
		moved_id := index.runtimes[dense].id
		index.runtime_by_id[moved_id] = dense
		// The moved chunk's entity_chunk entries still point to the correct
		// dense index because we only moved the dense storage, not the
		// per-entity membership.
	}
	pop(&index.runtimes)
	pop(&index.chunk_entities)
	delete_key(&index.runtime_by_id, id)
	return true
}

//* LOOKUP
chunk_index_contains :: #force_inline proc(index: ^Chunk_Index, id: Chunk_ID) -> bool {
	if !chunk_index_is_valid(index) do return false
	_, ok := index.runtime_by_id[id]
	return ok
}

chunk_index_get :: #force_inline proc(index: ^Chunk_Index, id: Chunk_ID) -> ^Chunk_Runtime {
	if !chunk_index_is_valid(index) do return nil
	dense, ok := index.runtime_by_id[id]
	if !ok do return nil
	return &index.runtimes[dense]
}

//* STATE
chunk_index_set_state :: proc(index: ^Chunk_Index, id: Chunk_ID, state: Chunk_Runtime_State) -> bool {
	rt := chunk_index_get(index, id)
	if rt == nil do return false
	rt.state = state
	if state == .Loaded || state == .Active {
		rt.loaded_tick = max(rt.loaded_tick, 0)
	}
	return true
}

//* SUBSYSTEM STATE BITS
// Mutate a chunk's subsystem-state bits. These are intentionally
// independent of `chunk_index_set_state` (which drives the streaming
// lifecycle): the lifecycle tells you whether the chunk is physically
// resident, the state bits tell you which subsystems should use it.

// Replace the full state mask in one call.
chunk_index_set_states :: proc(
	index: ^Chunk_Index,
	id: Chunk_ID,
	states: Chunk_States,
) -> bool {
	rt := chunk_index_get(index, id)
	if rt == nil do return false
	rt.states = states
	return true
}

// Set or clear a single state bit.
chunk_index_toggle_state :: proc(
	index: ^Chunk_Index,
	id: Chunk_ID,
	state: Chunk_State,
	on: bool,
) -> bool {
	rt := chunk_index_get(index, id)
	if rt == nil do return false
	if on {
		rt.states |= {state}
	} else {
		rt.states -= {state}
	}
	return true
}

// Reset all subsystem bits to zero (chunk is no longer participating in
// any subsystem). Streaming state / flags / bounds / entity membership
// are left untouched.
chunk_index_clear_states :: proc(index: ^Chunk_Index, id: Chunk_ID) -> bool {
	rt := chunk_index_get(index, id)
	if rt == nil do return false
	rt.states = {}
	return true
}

// Query helpers.
chunk_index_has_state :: proc(
	index: ^Chunk_Index,
	id: Chunk_ID,
	state: Chunk_State,
) -> bool {
	rt := chunk_index_get(index, id)
	if rt == nil do return false
	return state in rt.states
}

chunk_index_states :: #force_inline proc(
	index: ^Chunk_Index,
	id: Chunk_ID,
) -> Chunk_States {
	rt := chunk_index_get(index, id)
	if rt == nil do return {}
	return rt.states
}

//* ACTIVE / VISIBLE CHUNK SETS
// Each subsystem derives its own relevant chunk set from these flags.
// Renderer extraction is expected to consume the *Visible* set; gameplay
// simulation consumes *Simulated*; the server consumes *Replicated*; AI
// consumes *Navigable*. Counters are O(N) but allocation-free; iteration
// uses a callback so consumers can avoid per-frame allocation.

// Number of chunks currently flagged with `state`.
chunk_index_state_count :: proc(index: ^Chunk_Index, state: Chunk_State) -> int {
	if !chunk_index_is_valid(index) do return 0
	n := 0
	for &rt in index.runtimes {
		if state in rt.states do n += 1
	}
	return n
}

chunk_index_active_count :: #force_inline proc(index: ^Chunk_Index) -> int {
	return chunk_index_state_count(index, .Active)
}

chunk_index_visible_count :: #force_inline proc(index: ^Chunk_Index) -> int {
	return chunk_index_state_count(index, .Visible)
}

chunk_index_simulated_count :: #force_inline proc(index: ^Chunk_Index) -> int {
	return chunk_index_state_count(index, .Simulated)
}

chunk_index_replicated_count :: #force_inline proc(index: ^Chunk_Index) -> int {
	return chunk_index_state_count(index, .Replicated)
}

chunk_index_navigable_count :: #force_inline proc(index: ^Chunk_Index) -> int {
	return chunk_index_state_count(index, .Navigable)
}

chunk_index_loaded_state_count :: #force_inline proc(index: ^Chunk_Index) -> int {
	return chunk_index_state_count(index, .Loaded)
}

// Iterator callback: receives the chunk id and a stable pointer to the
// chunk runtime. Returning false stops iteration. The runtime pointer
// stays valid for the lifetime of the index, so consumers can read
// bounds / entity_count / entity list without copying.
Chunk_Visit_Proc :: proc(id: Chunk_ID, runtime: ^Chunk_Runtime, user_data: rawptr) -> bool

chunk_index_for_each_state :: proc(
	index: ^Chunk_Index,
	state: Chunk_State,
	visit: Chunk_Visit_Proc,
	user_data: rawptr = nil,
) -> bool {
	if !chunk_index_is_valid(index) || visit == nil do return false
	for &rt, dense in index.runtimes {
		if state in rt.states {
			if !visit(rt.id, &rt, user_data) do return false
		}
	}
	return true
}

chunk_index_for_each_active :: proc(
	index: ^Chunk_Index,
	visit: Chunk_Visit_Proc,
	user_data: rawptr = nil,
) -> bool {
	return chunk_index_for_each_state(index, .Active, visit, user_data)
}

chunk_index_for_each_visible :: proc(
	index: ^Chunk_Index,
	visit: Chunk_Visit_Proc,
	user_data: rawptr = nil,
) -> bool {
	return chunk_index_for_each_state(index, .Visible, visit, user_data)
}

chunk_index_for_each_simulated :: proc(
	index: ^Chunk_Index,
	visit: Chunk_Visit_Proc,
	user_data: rawptr = nil,
) -> bool {
	return chunk_index_for_each_state(index, .Simulated, visit, user_data)
}

chunk_index_for_each_replicated :: proc(
	index: ^Chunk_Index,
	visit: Chunk_Visit_Proc,
	user_data: rawptr = nil,
) -> bool {
	return chunk_index_for_each_state(index, .Replicated, visit, user_data)
}

chunk_index_for_each_navigable :: proc(
	index: ^Chunk_Index,
	visit: Chunk_Visit_Proc,
	user_data: rawptr = nil,
) -> bool {
	return chunk_index_for_each_state(index, .Navigable, visit, user_data)
}

// Allocate a snapshot of the chunks currently flagged with `state`.
// Caller owns the returned slice and must `delete` it. The Chunk_ID
// values are dense runtime indices that stay valid for the index's
// lifetime; consumers that need long-lived snapshots should resolve
// them before mutating the index further.
chunk_index_collect_state :: proc(
	index: ^Chunk_Index,
	state: Chunk_State,
	allocator: runtime.Allocator = context.allocator,
) -> []Chunk_ID {
	if !chunk_index_is_valid(index) do return nil
	out: [dynamic]Chunk_ID
	out = make(
		[dynamic]Chunk_ID,
		0,
		chunk_index_state_count(index, state),
		allocator,
	)
	for &rt in index.runtimes {
		if state in rt.states do append(&out, rt.id)
	}
	return out[:]
}

chunk_index_collect_active :: #force_inline proc(
	index: ^Chunk_Index,
	allocator: runtime.Allocator = context.allocator,
) -> []Chunk_ID {
	return chunk_index_collect_state(index, .Active, allocator)
}

chunk_index_collect_visible :: #force_inline proc(
	index: ^Chunk_Index,
	allocator: runtime.Allocator = context.allocator,
) -> []Chunk_ID {
	return chunk_index_collect_state(index, .Visible, allocator)
}

//* MEMBERSHIP
// Set an entity's chunk. Handles cross-boundary transitions:
//   - if the entity already had a chunk, it is removed from that chunk
//   - the new chunk's entity list is updated
//   - the entity_chunk reverse map is updated atomically
//   - the entity's per-chunk entity_count is kept consistent
// new_chunk == CHUNK_INVALID clears membership without reassigning.
// If new_chunk is neither CHUNK_INVALID nor a registered chunk, the call
// fails and the entity's prior membership is left untouched.
chunk_index_set_entity_chunk :: proc(
	index: ^Chunk_Index,
	entity: Entity,
	new_chunk: Chunk_ID,
) -> bool {
	if !chunk_index_is_valid(index) do return false
	if entity == ENTITY_INVALID do return false

	if new_chunk == CHUNK_INVALID {
		// Pure clear.
		chunk_index_remove_from_prev(index, entity)
		return true
	}

	dense, ok := index.runtime_by_id[new_chunk]
	if !ok do return false

	// Validate the new chunk before mutating the old one.
	chunk_index_remove_from_prev(index, entity)

	list := &index.chunk_entities[dense]
	append(list, entity)
	index.runtimes[dense].entity_count += 1
	index.entity_chunk[entity] = dense
	return true
}

//* INTERNAL
@(private = "file")
chunk_index_remove_from_prev :: proc(index: ^Chunk_Index, entity: Entity) {
	prev_dense, had := index.entity_chunk[entity]
	if !had do return
	if prev_dense < 0 || prev_dense >= len(index.chunk_entities) {
		delete_key(&index.entity_chunk, entity)
		return
	}
	prev_list := &index.chunk_entities[prev_dense]
	for i in 0 ..< len(prev_list) {
		if prev_list[i] == entity {
			ordered_remove(prev_list, i)
			if index.runtimes[prev_dense].entity_count > 0 {
				index.runtimes[prev_dense].entity_count -= 1
			}
			break
		}
	}
	delete_key(&index.entity_chunk, entity)
}

// Clear an entity's chunk membership. Idempotent.
chunk_index_clear_entity :: proc(index: ^Chunk_Index, entity: Entity) -> bool {
	if !chunk_index_is_valid(index) do return false
	return chunk_index_set_entity_chunk(index, entity, CHUNK_INVALID)
}

chunk_index_entity_chunk :: #force_inline proc(index: ^Chunk_Index, entity: Entity) -> Chunk_ID {
	if !chunk_index_is_valid(index) do return CHUNK_INVALID
	dense, ok := index.entity_chunk[entity]
	if !ok do return CHUNK_INVALID
	if dense < 0 || dense >= len(index.runtimes) do return CHUNK_INVALID
	return index.runtimes[dense].id
}

chunk_index_chunk_entities :: #force_inline proc(index: ^Chunk_Index, id: Chunk_ID) -> []Entity {
	if !chunk_index_is_valid(index) do return nil
	dense, ok := index.runtime_by_id[id]
	if !ok do return nil
	return index.chunk_entities[dense][:]
}

chunk_index_chunk_entity_count :: #force_inline proc(index: ^Chunk_Index, id: Chunk_ID) -> int {
	if !chunk_index_is_valid(index) do return 0
	dense, ok := index.runtime_by_id[id]
	if !ok do return 0
	return len(index.chunk_entities[dense])
}

//* CHUNK GRID HELPERS
// Compute the Chunk_ID that contains `world_pos` for the given chunk_size.
// Chunk_ID is encoded as a stable (x, y, z) triple packed into u64:
//   bits  0..21 : x  (signed, ~2M cells per axis)
//   bits 22..43 : z  (signed)
//   bits 44..63 : y  (signed, lowest resolution reserved for map / generation)
chunk_calculate_from_position :: proc(world_pos: mth.Vec3, chunk_size: f32) -> Chunk_ID {
	if chunk_size <= 0 do return CHUNK_INVALID
	cell := 1.0 / chunk_size
	cx := i64(math.floor(world_pos.x * cell))
	cy := i64(math.floor(world_pos.y * cell))
	cz := i64(math.floor(world_pos.z * cell))
	// Clamp to 22-bit signed range.
	CLAMP :: 0x1FFFFF  // 21 bits + sign
	if cx > CLAMP  do cx = CLAMP
	if cx < -CLAMP do cx = -CLAMP
	if cy > CLAMP  do cy = CLAMP
	if cy < -CLAMP do cy = -CLAMP
	if cz > CLAMP  do cz = CLAMP
	if cz < -CLAMP do cz = -CLAMP
	xu := u64(cx) & 0x3FFFFF
	zu := u64(cz) & 0x3FFFFF
	yu := u64(cy) & 0x3FFFFF
	return Chunk_ID(xu | (zu << 22) | (yu << 44))
}

// Inverse of chunk_calculate_from_position: produce the world-space AABB
// of a chunk given its id and chunk_size.
chunk_calculate_bounds :: proc(id: Chunk_ID, chunk_size: f32) -> mth.AABB {
	if chunk_size <= 0 do return mth.AABB{}
	xu := u64(id) & 0x3FFFFF
	zu := (u64(id) >> 22) & 0x3FFFFF
	yu := (u64(id) >> 44) & 0x3FFFFF
	sx :: 22
	sy :: 22
	cx := i64(xu) - (i64(xu & (u64(1) << (sx - 1))) << 1)
	cy := i64(yu) - (i64(yu & (u64(1) << (sy - 1))) << 1)
	cz := i64(zu) - (i64(zu & (u64(1) << (sx - 1))) << 1)
	return mth.AABB {
		min = {f32(cx) * chunk_size, f32(cy) * chunk_size, f32(cz) * chunk_size},
		max = {f32(cx + 1) * chunk_size, f32(cy + 1) * chunk_size, f32(cz + 1) * chunk_size},
	}
}