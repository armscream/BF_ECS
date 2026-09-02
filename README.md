# BF_ECS v0.0.1

**An entity component system for Bifrost Engine, Extends ODE_ECS functionality**

## Installation

- To install BF_ECS, simply clone the repository into your project's `modules` directory.
- Clone ode_ecs in the BF_ECS directory. <git clone https://github.com/odin-engine/ode_ecs.git>
- In your project's directory, run ./rune manifest to generate a manifest file for this module, if you don't have one already.
- Add the following to your project's manifest file <project.toml> in the modules section:
[[modules]]
name = "BF_ECS"
enabled = true
required = true
version = { major = 0, minor = 0, patch = 1 }
- Run ./rune run <DEBUG/RELEASE/EDITOR>

## Dependencies

- BF_DAG

## Current State

- In progress

## License

- Just as all Core Modules, this module inherets Bifrost Engine's licensing agreement.

## Creditaion

- Authors of ODE_ECS for the ECS implementation.