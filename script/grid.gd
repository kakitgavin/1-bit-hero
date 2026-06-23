extends ReferenceRect

@onready var enemy_location = $"../EnemyLocation"

enum GameState { WAIT_FOR_INPUT, SWAPPING, CHECK_MATCHES, FALLING}
var current_state: GameState = GameState.WAIT_FOR_INPUT

var column: int = 5 #in tiles
var row: int = 5 #in tiles

var grid: Array[Node2D] = []
var player_idx: int = 0

var possible_piece: Array = [
	preload("res://scene/piece/sword_piece.tscn"),
	preload("res://scene/piece/shield_piece.tscn"),
	preload("res://scene/piece/wand_piece.tscn"),
	preload("res://scene/piece/potion_piece.tscn"),
	preload("res://scene/piece/bow_piece.tscn")
]

var player_piece: PackedScene = preload("res://scene/piece/player_piece.tscn")
var enemy_piece: PackedScene = preload("res://scene/enemy/slime_enemy.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	init_grid()
	init_enemy()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if current_state != GameState.WAIT_FOR_INPUT:
		return
	#conditions so that player wont move right if its at the edge
	if Input.is_action_just_pressed('ui_right') and player_idx % column != column - 1:
		player_swap(1)
	elif Input.is_action_just_pressed('ui_left') and player_idx % column != 0:
		player_swap(-1)
	elif Input.is_action_just_pressed('ui_up'):
		player_swap(-column)
	elif Input.is_action_just_pressed('ui_down'):
		player_swap(column)

func init_grid() -> void:
	#visual size for the frame
	size.x = column * Globals.TILE_SIZE + 1
	size.y = row * Globals.TILE_SIZE + 1
	
	grid.resize(column * row)
	
	#init grid first
	for x in range(1, column * row):
		spawn_piece_to_index(x)
		
	#check if there is matches, if true clear them and generate new pieces again
	while(check_and_clear_matches()):
		for x in range(1, column * row):
			if grid[x] == null:
				spawn_piece_to_index(x)
	
	#add player when the board is settled
	var player = player_piece.instantiate()
	add_child(player)
	grid[player_idx] = player

func init_enemy() -> void:
	var enemy = enemy_piece.instantiate()
	enemy.position = enemy_location.position
	add_child(enemy)

func player_swap(pos_change: int) -> void:
	enter_state(GameState.SWAPPING)
	
	var target_idx: int = player_idx + pos_change
	
	#exit function early if player try to move outside of grid
	if target_idx >= grid.size() or target_idx < 0:
		current_state = GameState.WAIT_FOR_INPUT
		return
		
	var piece_to_swap = grid[target_idx]
	var player = grid[player_idx]
	
	#create swapping animation and update position with tween
	var tween = create_tween().set_parallel(true)
	tween.tween_property(player, "position", piece_to_swap.position, 0.1)
	if piece_to_swap:
		tween.tween_property(piece_to_swap, "position", player.position, 0.1)
	
	#update grid data
	grid[player_idx] = piece_to_swap
	grid[target_idx] = player
	player_idx = target_idx
	
	tween.finished.connect(func():
		enter_state(GameState.CHECK_MATCHES)
	)

func check_and_clear_matches() -> bool:
	
	# Using a Dictionary as a HashSet to store unique indices to delete
	var matched_indices: Dictionary = {}

	# 1. HORIZONTAL SCAN
	for r in range(row):
		for c in range(column - 2): # Stop 2 tiles early because we look 2 tiles ahead
			var idx1 = r * column + c
			var idx2 = r * column + c + 1
			var idx3 = r * column + c + 2
			
			if is_match_3(idx1, idx2, idx3):
				matched_indices[idx1] = true
				matched_indices[idx2] = true
				matched_indices[idx3] = true

	# 2. VERTICAL SCAN
	for c in range(column):
		for r in range(row - 2): # Stop 2 tiles early because we look 2 rows down
			var idx1 = r * column + c
			var idx2 = (r + 1) * column + c
			var idx3 = (r + 2) * column + c
			
			if is_match_3(idx1, idx2, idx3):
				matched_indices[idx1] = true
				matched_indices[idx2] = true
				matched_indices[idx3] = true

	# 3. RESOLUTION PHASE
	if matched_indices.is_empty():
		return false # No matches found
	
	for idx in matched_indices.keys():
		if grid[idx]:
			grid[idx].queue_free()
			grid[idx] = null
			
	return true # Matches successfully cleared

func grid_falling() -> void:
	var tween = create_tween().set_parallel(true)
	var has_animations = false
	
	for c in range(column):
		var spawn_offset: int = 0
		#scan from bottom to top
		for r in range(row - 1, -1, -1):
			var current_idx = r * column + c
			var fall_speed: float = 100
			var distance: float = 0.0
			var time_to_fall: float = 0.0
			
			#case 1: top row is null, instantly spawn a piece
			if r == 0 and grid[current_idx] == null:
				spawn_offset += 1
				
				distance = spawn_offset * Globals.TILE_SIZE
				time_to_fall = distance / fall_speed
				
				var piece = possible_piece[randi() % possible_piece.size()].instantiate()
				piece.position = Vector2i(c * Globals.TILE_SIZE, -spawn_offset * Globals.TILE_SIZE)
				add_child(piece)
				
				tween.tween_property(piece, "position", grid_to_pixel(current_idx), time_to_fall)
				has_animations = true
				
				grid[current_idx] = piece
				break
			
			#case 2, empty space is found proceed to look for a piece above
			if grid[current_idx] == null:
				var piece_found = false
				#look for the nearest top piece
				for lookup_r in range(r - 1, -1, -1):
					
					var above_idx = lookup_r * column + c
					if grid[above_idx] != null:
						distance = (r - lookup_r) * Globals.TILE_SIZE
						time_to_fall = distance / fall_speed
						
						tween.tween_property(grid[above_idx], "position", grid_to_pixel(current_idx), time_to_fall)
						has_animations = true
						
						grid[current_idx] = grid[above_idx]
						grid[above_idx] = null
						
						#update player pos if player is falling
						if grid[current_idx].scene_file_path == "res://scene/piece/player_piece.tscn":
							player_idx = current_idx
						
						piece_found = true
						break
					
				#case 3: no piece available, proceed to spawn one
				if not piece_found:
					spawn_offset += 1
					
					distance = (r + spawn_offset) * Globals.TILE_SIZE
					time_to_fall = distance / fall_speed
					
					var piece = possible_piece[randi() % possible_piece.size()].instantiate()
					piece.position = Vector2i(c * Globals.TILE_SIZE, -spawn_offset * Globals.TILE_SIZE)
					add_child(piece)
					
					tween.tween_property(piece, "position", grid_to_pixel(current_idx), time_to_fall)
					has_animations = true
					
					grid[current_idx] = piece

	if has_animations:
		# This signal fires automatically when ALL properties in the tween finish animating
		tween.finished.connect(func():
			enter_state(GameState.CHECK_MATCHES)
		)
	else:
		tween.kill()
		enter_state(GameState.WAIT_FOR_INPUT)

func enter_state(new_state: GameState) -> void:
	current_state = new_state
	
	match new_state:
		GameState.CHECK_MATCHES:
			if check_and_clear_matches():
				enter_state(GameState.FALLING)
			else:
				enter_state(GameState.WAIT_FOR_INPUT)
		GameState.FALLING:
			grid_falling()

#----------helper function-----------------

#convert grid index to position on grid
func grid_to_pixel(index: int) -> Vector2:
	return Vector2(index % column * Globals.TILE_SIZE, index / column * Globals.TILE_SIZE)

func spawn_piece_to_index(index: int) -> void:
	var piece = possible_piece[randi() % possible_piece.size()].instantiate()
	piece.position = grid_to_pixel(index)
	add_child(piece)
	grid[index] = piece

func is_match_3(iA: int, iB: int, iC: int) -> bool:
	if grid[iA] == null or grid[iB] == null or grid[iC] == null:
		return false
	return grid[iA].scene_file_path == grid[iB].scene_file_path and grid[iB].scene_file_path == grid[iC].scene_file_path
