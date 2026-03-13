extends Node

# NetworkManager — ENet setup, connection handling, QR code generation
# TODO Phase 3: implement ENet peer as host or client
# TODO Phase 3: generate QR code with local IP for easy joining
# TODO Phase 3: handle player connect/disconnect events

var is_host: bool = false
var local_ip: String = ""
var connected_peers: Array = []


func _ready() -> void:
	pass
