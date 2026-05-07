class_name MatchRenderer
extends Node2D

# Renders a MatchState to screen. Reads ResolveResult.events to render
# attack overlays + destruction effects. Pure consumer of state — never
# writes back. The resolver remains a pure function (ADR-0013).
#
# Plan node: plan/m0/07-dev-play-mode/07b1-renderer-and-camera.md
#
# Chunk 2 ships only the API stubs and scene wiring. Chunk 3 fills in
# bind_state() with actual sprite spawning + camera framing. Chunk 4
# fills in render_step() with attack overlays + reconciliation.

const ENTITY_VIEW_SCENE_PATH := "res://scenes/entity_view.tscn"

# Set externally before bind_state, or auto-loaded from canonical path.
const DEFAULT_VISUALS_PATH := "res://data/entity_visuals.tres"

@onready var _entities_root: Node2D = $Entities
@onready var _terrain: TileMapLayer = $Terrain
@onready var _camera: Camera2D = $Camera2D

var _state: MatchState = null
var _registry: EntityRegistry = null
var _visuals: EntityVisuals = null
# entity id -> EntityView node. Lookup table to avoid scanning $Entities.
var _views_by_id: Dictionary = {}


# Initial bind: take a freshly-loaded MatchState and populate the scene
# tree to match. Replaces any existing rendered state.
func bind_state(state: MatchState, registry: EntityRegistry) -> void:
	_state = state
	_registry = registry
	_visuals = load(DEFAULT_VISUALS_PATH) as EntityVisuals
	# chunk 3: spawn EntityViews for every entity, paint terrain, fit camera
	pass


# Apply a turn's resolution: reconcile entity views vs new_state, render
# the events list (attack lines, damage labels, destruction fades).
func render_step(new_state: MatchState, events: Array) -> void:
	_state = new_state
	# chunk 4: reconcile views, render events, append to combat log
	pass


# Lookup helpers used by tests.


func get_entity_view(entity_id: int) -> EntityView:
	return _views_by_id.get(entity_id)


func entity_view_count() -> int:
	return _views_by_id.size()
