# Aoi Embedded Godot Sandbox — 2.9.0 foundation

## Purpose

The mobile app must remain useful when no PC is available. This milestone adds an on-device Godot API explorer and a constrained native scene builder. It does **not** embed the Godot Editor, and it does not execute arbitrary imported GDScript inside the Aoi process.

## Implemented

- `GodotSandbox.ensure_index()` enumerates the current engine's live `ClassDB` class list. Godot 4.8 beta1 reports 1,088 indexed classes in the reviewed environment.
- `search_classes()` filters the compact class-name index.
- `inspect_class()` lazily reads a selected class's methods, argument types, properties, signals, parent and instantiability. Results are cached per class, rather than serializing every signature at startup.
- `validate_gdscript()` asks Godot's own `GDScript.reload()` compiler path to validate source. It has a 256 KB size cap. Parser diagnostics are emitted by Godot; a false result means the script must not be saved by the Studio's new-script flow.
- `write_project_text()` writes only safe project-relative paths and enforces a 256 KB limit.
- `create_scene()` builds ordinary `.tscn` resources using a restricted node allow-list, bounded to 80 child nodes. Only explicitly permitted properties can be assigned. CollisionShape2D supports generated rectangle, circle and capsule shapes without arbitrary Resource injection.
- Studio exposes API Explorer, starter 2D scene generation, local scene preview and GDScript validation through the Sources toolbox.
- The starter scene contains a Node2D root, backdrop, CharacterBody2D player, capsule collision, Camera2D, StaticBody2D ground, rectangle collision and ground visual. It is a scene/physics scaffold, not a completed playable platformer: no movement script is attached yet.

## Safety boundaries

- The sandbox does not execute arbitrary GDScript, shell commands or native code.
- Imported `.gd` files are treated as untrusted source. They can be inspected and compiler-validated, but are not automatically executed in the main app.
- The scene builder instantiates only its hard-coded node allow-list and applies only explicitly allowed properties.
- This is not a full Godot editor and cannot guarantee compatibility with every imported plugin, GDExtension, shader, editor-only resource or project setting.

## Current limitations / next steps

1. Add project ZIP import/export on-device with archive traversal, file-size and compression-ratio preflight.
2. Expand the scene blueprint schema for TileMapLayer, animation, resources, collision layers and input maps.
3. Build a restricted playable 2D runtime with touch controls and physics, then visual-test it on a real Android device.
4. Add syntax diagnostics with source line/column details and dependency-aware compile checks for multi-file projects.
5. Add an explicit preview/test report with screenshot capture and regression comparisons.

## Test evidence

Godot 4.8 beta1 tests cover live class indexing, class member inspection, valid GDScript compilation, validation size limits, path traversal rejection, native file writes, native scene packing, collision shape creation and rejection of unapproved node types. The UI suite covers API Explorer opening/selection, local scene generation and local preview without a PC.
