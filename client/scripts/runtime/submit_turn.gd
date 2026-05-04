class_name SubmitTurn
extends Resource

# What one player submits at the end of their turn.
#
# - `orders` is the list of NEW orders issued this turn (move, attack,
#   build, cancel, etc.). Persistent state (a unit's running MOVE) is
#   NOT re-submitted; the resolver carries it across turns via
#   Entity.persistent_order.
# - `surrender` is a per-turn flag rather than an order in `orders`,
#   per plan/m0/03 ("Surrender ... goes in SubmitTurn flag, not the
#   per-unit queue"). Removes the special-case entity_id=-1 sentinel
#   from EntityOrder.

@export var orders: Array[EntityOrder] = []
@export var surrender: bool = false


func clone() -> SubmitTurn:
	# Deep clone — each EntityOrder is independently copied so a caller
	# can mutate the clone's orders (or any field inside them, including
	# target_priority_chain) without affecting the original.
	var c := SubmitTurn.new()
	c.orders = []
	for o in orders:
		if o != null:
			c.orders.append(o.clone())
		else:
			c.orders.append(null)
	c.surrender = surrender
	return c
