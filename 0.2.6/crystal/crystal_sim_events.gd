class_name CrystalSimEvents
extends RefCounted
## Typed change events emitted by CrystalSimulation (discovery/update only — no scene access).

enum Kind {
	DEPTH_CHANGED = 1,
	DEPTH_CLEARED = 2,
	FLOW_BATCH = 3,
	MESH_DIRTY = 4,
	POWER_DELTA = 5,
	STATS = 6,
	ABSORPTION_READY = 7,
	RUIN_ABSORPTION_READY = 8,
}


static func depth_changed(pos: Vector2i) -> Dictionary:
	return {"kind": Kind.DEPTH_CHANGED, "pos": pos}


static func depth_cleared(pos: Vector2i) -> Dictionary:
	return {"kind": Kind.DEPTH_CLEARED, "pos": pos}


static func flow_batch(changed: Array, mesh_dirty: Array, new_cells: int) -> Dictionary:
	return {
		"kind": Kind.FLOW_BATCH,
		"changed": changed,
		"mesh_dirty": mesh_dirty,
		"new_cells": new_cells,
	}


static func mesh_dirty(positions: Array) -> Dictionary:
	return {"kind": Kind.MESH_DIRTY, "positions": positions}


static func power_delta(amount: float) -> Dictionary:
	return {"kind": Kind.POWER_DELTA, "amount": amount}


static func stats(volume: float, cells: int) -> Dictionary:
	return {"kind": Kind.STATS, "volume": volume, "cells": cells}


static func absorption_ready(pos: Vector2i, tile_id: int, feat: Dictionary) -> Dictionary:
	return {
		"kind": Kind.ABSORPTION_READY,
		"pos": pos,
		"tile_id": tile_id,
		"feat": feat,
	}


static func ruin_absorption_ready(center: Vector2i) -> Dictionary:
	return {"kind": Kind.RUIN_ABSORPTION_READY, "center": center}
