// Engine/src/Modules/BF_ECS/Entity.odin
package BF_ECS

// Entity with generational handles, will itterate further on this.
Entity :: struct {
	id:         u32,
	generation: u32,
}
