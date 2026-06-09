@tool
class_name SubmitTurn
extends Resource

# What one player submits at the end of their turn.
#
# - `orders` is the list of orders submitted for this turn (move, attack,
#   build, cancel, etc.). Long-range move assistance lives in the input
#   layer, which re-submits unfinished movement as ordinary orders; the
#   resolver does not carry hidden move orders across turns.
# - `surrender` is a per-turn flag rather than an order in `orders`,
#   per plan/m0/03 ("Surrender ... goes in SubmitTurn flag, not the
#   per-unit queue"). Removes the special-case entity_id=-1 sentinel
#   from EntityOrder.

@export var orders: Array[EntityOrder] = []
@export var surrender: bool = false


func clone() -> SubmitTurn:
	# Deep clone — each EntityOrder is independently copied so a caller
	# can mutate the clone's orders without affecting the original.
	var c := SubmitTurn.new()
	c.orders = []
	for o in orders:
		if o != null:
			c.orders.append(o.clone())
		else:
			c.orders.append(null)
	c.surrender = surrender
	return c
