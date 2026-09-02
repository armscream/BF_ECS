package BF_ECS

import "core:math"
import "core:mem"

import "../../Core"
import mth "../../Core/BF_Math"

// Spatial_Settings is the alias through which callers reach the
// project-wide world partition settings. Defined in Core so the
// project's TOML schema remains the single source of truth.
Spatial_Settings :: Core.Spatial_Settings

// ============================================================================
// Coordinates
//
// Coordinates are integer grid coordinates. They are intentionally separate
// from world-space positions.
Chunk_Coord :: struct {
	x: i32,
	y: i32,
	z: i32,
}

Cell_Coord :: struct {
	x: i32,
	y: i32,
	z: i32,
}

Local_Cell :: struct {
	x: u32,
	y: u32,
	z: u32,
}


// ===============================
// Spatial Index
//
// The first implementation uses a dense cell index inside each world chunk.
//
// We deliberately separate the index from the Chunk itself.
//
// The ECS continues to own component data:
//
//     Archetypes
//     Sparse Sets
//
// The partition owns spatial membership:
//
//     Chunk -> Cell -> Entity IDs
//
// The eventual representation is:
//
//     counts[cell]
//     offsets[cell]
//     entities[]
//
// This supports a very efficient counting/scatter rebuild:
//
//     1. Count entities per cell.
//     2. Prefix sum counts -> offsets.
//     3. Scatter entity IDs into entities[].
//
// This gives compact contiguous entity ranges for every cell.
//
Spatial_Index :: struct {
	cell_count:   u32,

	// Number of entities currently belonging to each cell.
	counts:       []u32,

	// Starting offset into entities[] for each cell.
	offsets:      []u32,

	// Entity IDs packed by cell.
	entities:     []Entity,

	// Number of entities currently stored.
	entity_count: u32,

	// Allocator used by this index.
	allocator:    mem.Allocator,
}


// ===========================
// World Chunk
//
// A chunk is a spatial partitioning unit.
//
// It does NOT contain ECS component storage.
//
// Component data remains in archetypes/sparse sets.
//
// A chunk only answers:
//
//     "Which entities currently occupy this region?"
//
// This makes chunks useful for:
//
//     - replication
//     - world streaming
//     - asset streaming
//     - AI queries
//     - gameplay proximity
//     - audio
//     - editor spatial selection
//
// Physics is intentionally not coupled to this structure. Physics may build
// its own BVH/broad phase.
//
World_Chunk :: struct {
	coord:    Chunk_Coord,
	spatial:  Spatial_Index, // Local spatial index

	// Dynamic/dormant entities occupying this chunk
	entities: [dynamic]Entity,
	// Static world/rendering information
	static:   Static_Chunk_Data, // Could be render objects?
	state:    Chunk_State, // Chunk lifecycle.
	// Set when membership changes and the spatial index needs rebuilding.
	using dirty: Chunk_Dirty_Flags,
	using flags: Chunk_Flags,
}

Static_Chunk_Data :: struct {
	// TODO: Add static world/rendering information
	// Static render objects
	//meshes: [dynamic]Render_Object,

	// Terrain/world data
	//terrain: Terrain_Data, (height data?)

	// Potentially baked worl data
	//lighting: ... (could even do wind effects, like direction and strength)
}

// Flags give a quick lookup to what data is available in a chunk.
Chunk_Flags :: struct {
	Has_Static:     bool,
	Has_Dynamic:    bool,
	Has_Dormant:    bool,
	Has_Terrain:    bool,
	Has_Replicated: bool,
}
// Marks what data needs to be updated
Chunk_Dirty_Flags  :: struct {
	Static:     bool,
	Dynamic:    bool,
	Dormant:    bool,
	Terrain:    bool,
	Replicated: bool,
}

// ========================
// World Spatial Partition
World_Spatial :: struct {
	settings:  Core.Spatial_Settings,

	// Only chunks containing entities are allocated.
	chunks:    map[Chunk_Coord]^World_Chunk,
	allocator: mem.Allocator,
}


// =========================
// Initialization
world_spatial_init :: proc(
	ws: ^World_Spatial,
	settings: Spatial_Settings,
	allocator: mem.Allocator,
) -> bool {
	if settings.chunk_size == 0 do return false

	if settings.cell_size <= 0 do return false

	ws.settings = settings
	ws.allocator = allocator

	ws.chunks = make(map[Chunk_Coord]^World_Chunk, allocator)

	return true
}


// =============================
// Destruction
world_spatial_destroy :: proc(ws: ^World_Spatial) {
	for _, chunk in ws.chunks {
		spatial_index_destroy(&chunk.spatial)
		free(chunk)
	}
	delete(ws.chunks)
}


// ============================
// Coordinate Conversion
// ============================
// Convert world-space position to chunk coordinate.
//
// Example:
//
//     chunk_size = 16
//     cell_size  = 4m
//
//     chunk width = 64m
//
//     position  0m..63.999m -> chunk 0
//     position 64m..127.9m  -> chunk 1
//     position -1m          -> chunk -1
//
// Negative coordinates are intentionally handled through floor rather than truncation.
world_to_chunk :: proc(ws: ^World_Spatial, position: mth.Vec3) -> Chunk_Coord {
	chunk_world_size := f32(ws.settings.chunk_size) * ws.settings.cell_size

	return Chunk_Coord {
		x = i32(math.floor(position.x / chunk_world_size)),
		y = i32(math.floor(position.y / chunk_world_size)),
		z = i32(math.floor(position.z / chunk_world_size)),
	}
}

// Convert world position to the global cell coordinate.
world_to_cell :: proc(ws: ^World_Spatial, position: mth.Vec3) -> Cell_Coord {
	cell := ws.settings.cell_size

	return Cell_Coord {
		x = i32(math.floor(position.x / cell)),
		y = i32(math.floor(position.y / cell)),
		z = i32(math.floor(position.z / cell)),
	}
}

// Convert world position to the local cell inside its chunk.
//
// The result is always:
//
//     0 <= x < chunk_size
//     0 <= y < chunk_size
//     0 <= z < chunk_size
//
// even for negative world coordinates.
world_to_local_cell :: proc(ws: ^World_Spatial, position: mth.Vec3) -> Local_Cell {
	global := world_to_cell(ws, position)
	chunk := world_to_chunk(ws, position)

	size := i32(ws.settings.chunk_size)

	return Local_Cell {
		x = u32(global.x - chunk.x * size),
		y = u32(global.y - chunk.y * size),
		z = u32(global.z - chunk.z * size),
	}
}

// Convert a chunk coordinate to the world-space origin of that chunk.
chunk_origin :: proc(ws: ^World_Spatial, coord: Chunk_Coord) -> mth.Vec3 {
	chunk_world_size := f32(ws.settings.chunk_size) * ws.settings.cell_size

	return mth.Vec3 {
		f32(coord.x) * chunk_world_size,
		f32(coord.y) * chunk_world_size,
		f32(coord.z) * chunk_world_size,
	}
}


// =================================
// Cell Indexing
//
// Convert a local cell coordinate into a dense linear index.
//
// 3D: index = x + y*S + z*S*S
// 2D: index = x + y*S
// where S = chunk_size.
local_cell_index :: proc(ws: ^World_Spatial, cell: Local_Cell) -> u32 {
	s := u32(ws.settings.chunk_size)

	// settings.cubic is the dimensional flag exposed by
	// Core.Spatial_Settings (true = 3D, false = 2D). We test on it
	// directly so the file does not depend on a local enum.
	if ws.settings.cubic do return u32(cell.x) + u32(cell.y) * s + u32(cell.z) * s * s
	return u32(cell.x) + u32(cell.y) * s
}

cells_per_chunk :: proc(ws: ^World_Spatial) -> u32 {
	s := ws.settings.chunk_size

	if ws.settings.cubic do return s * s * s
	return s * s
}

spatial_index_init :: proc(
	index: ^Spatial_Index,
	cell_count: u32,
	allocator: mem.Allocator,
) -> bool {
	if cell_count == 0 do return false

	index.cell_count = cell_count
	index.allocator = allocator

	index.counts = make([]u32, int(cell_count), allocator)
	index.offsets = make([]u32, int(cell_count), allocator)

	index.entities = nil
	index.entity_count = 0

	return true
}

spatial_index_destroy :: proc(index: ^Spatial_Index) {
	if index.counts != nil {
		delete(index.counts, index.allocator)
	}

	if index.offsets != nil {
		delete(index.offsets, index.allocator)
	}

	if index.entities != nil {
		delete(index.entities, index.allocator)
	}

	index^ = {}
}

world_spatial_create_chunk :: proc(ws: ^World_Spatial, coord: Chunk_Coord) -> ^World_Chunk {
	if chunk, ok := ws.chunks[coord]; ok do return chunk

	chunk := new(World_Chunk, ws.allocator)

	chunk.coord = coord
	chunk.dirty = false
	chunk.entity_count = 0

	cell_count := cells_per_chunk(ws)

	if !spatial_index_init(&chunk.spatial, cell_count, ws.allocator) {
		free(chunk, ws.allocator)
		return nil
	}
	ws.chunks[coord] = chunk

	return chunk
}

world_spatial_find_chunk :: proc(ws: ^World_Spatial, coord: Chunk_Coord) -> (^World_Chunk, bool) {
	if chunk, ok := ws.chunks[coord]; ok do return chunk, true

	return nil, false
}

world_spatial_remove_chunk :: proc(ws: ^World_Spatial, coord: Chunk_Coord) {
	chunk, ok := ws.chunks[coord]

	if !ok do return

	spatial_index_destroy(&chunk.spatial)

	free(chunk, ws.allocator)
	delete_key(&ws.chunks, coord)
}

chunk_is_empty :: proc(chunk: ^World_Chunk) -> bool {
	return chunk.entity_count == 0
}
