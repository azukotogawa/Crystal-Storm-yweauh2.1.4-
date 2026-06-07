class_name ChunkManager
extends Node3D

@export var chunk_scene: PackedScene
@export var texture: Texture2D

const RENDER_DISTANCE := 4

var chunks: Dictionary[Vector2i, ChunkView] = {}
var job_queue := []
var mutex := Mutex.new()
var semaphore := Semaphore.new() 
var thread := Thread.new()
var exit_thread := false        
var pending := {}

var player: Node3D
var world: InfiniteNoiseWorld

const CHUNK_VIEW_SCENE = preload("res://scenes/ChunkView.tscn")

const FACE_TOP := 0
const FACE_SIDE := 1

func _ready():
	add_to_group("chunk_manager")
	exit_thread = false
	thread.start(_worker)
	
	player = get_tree().get_first_node_in_group("player")
	world = get_tree().get_first_node_in_group("world")
	
	call_deferred("_setup_dependencies")                                        
																				
func _setup_dependencies():                                                     
	player = get_tree().get_first_node_in_group("player")                       
	world = get_tree().get_first_node_in_group("world")                         
																				
	if player == null:                                                          
		print("WARNING: Player node (group 'player') not found!")               
	if world == null:                                                           
		print("WARNING: World node (group 'world') not found!")   

func _exit_tree():
	mutex.lock()
	exit_thread = true
	mutex.unlock()
	semaphore.post() 
	thread.wait_to_finish()

func request_chunk(coord: Vector2i):
	if chunks.has(coord) or pending.has(coord):
		return

	pending[coord] = true

	mutex.lock()
	job_queue.append(coord)
	mutex.unlock()
	semaphore.post() 

func _worker():                                                                 
	print("Chunk generation thread started successfully.")                      
	while not exit_thread:                                                      
		semaphore.wait() # Blocks until semaphore.post() is called              
		
		mutex.lock()                                                            
		if exit_thread:                                                         
			mutex.unlock()                                                      
			break                                                               

		if job_queue.is_empty():                                                
			mutex.unlock()                                                      
			continue             
														   
		var coord = job_queue[0]
		job_queue.pop_front()                                                             
		mutex.unlock()                                                          

		var data := ChunkData.new(coord)                                        
		_generate_chunk(data)
		
		var packed_mesh_arrays = _build_mesh_in_thread(data)                    

		# Hand off data to the main loop safely                                 
		call_deferred("_on_chunk_ready", data, packed_mesh_arrays)                                                                            

func _build_mesh_in_thread(data: ChunkData) -> Dictionary:
	var out_quads := []

	for y in range(ChunkData.HEIGHT):
		var mask = build_top_mask(data, y)
		greedy_top_faces(mask, y, out_quads)

	var count = out_quads.size()
	var transforms: Array[Transform3D] = []
	var custom_colors := PackedColorArray()
	
	transforms.resize(count)
	custom_colors.resize(count)

	var chunk_offset_x = float(data.position.x * ChunkData.SIZE)
	var chunk_offset_z = float(data.position.y * ChunkData.SIZE)

	for i in range(count):
		var q = out_quads[i]

		var world_x = float(q.x) + chunk_offset_x
		var world_y = float(q.y) 
		var world_z = float(q.z) + chunk_offset_z

		var t := Transform3D.IDENTITY
		t.basis = t.basis.scaled(Vector3(float(q.w), 1.0, float(q.h)))
		t.origin = Vector3(
			world_x + float(q.w) * 0.5,
			world_y + 0.5, 
			world_z + float(q.h) * 0.5
		)
		transforms[i] = t

		# Localized safe fallback checking to avoid Dictionary lookup thread deadlocks
		var atlas = Vector2i(6, 0)
		if VoxelTypes.ATLAS_COORDS.has(q.type):
			atlas = VoxelTypes.ATLAS_COORDS[q.type]
		
		# STABLE ARRAYS WAY: Map attributes cleanly to floating points
		# Red = Column, Green = Row
		# Blue = Encodes FACE type in whole number, encodes QUAD HEIGHT in decimals!
		# Alpha = Encodes QUAD WIDTH directly
		var encoded_face_and_height = float(FACE_TOP) + (float(q.h) / 100.0)

		custom_colors[i] = Color(
			float(atlas.x) / 255.0,
			float(atlas.y) / 255.0,
			encoded_face_and_height,
			float(q.w)
		)

	return {
		"transforms": transforms,
		"custom_colors": custom_colors,
		"count": count
	}
	
func build_top_mask(data: ChunkData, y: int) -> Array:
	var mask := []
	mask.resize(ChunkData.SIZE)

	for x in range(ChunkData.SIZE):
		mask[x] = []
		mask[x].resize(ChunkData.SIZE)

		for z in range(ChunkData.SIZE):
			var voxel = data.get_voxel(x, y, z)

			if voxel == VoxelTypes.AIR:
				mask[x][z] = 0
				continue

			if y + 1 < ChunkData.HEIGHT and data.get_voxel(x, y + 1, z) != VoxelTypes.AIR:
				mask[x][z] = 0
				continue

			mask[x][z] = voxel

	return mask
	
func greedy_top_faces(mask: Array, y: int, out: Array):
	var used := []
	used.resize(ChunkData.SIZE)

	for x in range(ChunkData.SIZE):
		used[x] = []
		used[x].resize(ChunkData.SIZE)

	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):

			if used[x][z]:
				continue

			var voxel_type = mask[x][z]

			if voxel_type == 0:
				continue

			var w := 1
			while x + w < ChunkData.SIZE:
				if used[x+w][z]:
					break
				if mask[x+w][z] != voxel_type:
					break
				w += 1

			var h := 1
			var stop := false
			while z + h < ChunkData.SIZE and !stop:
				for i in range(w):
					if used[x+i][z+h]:
						stop = true
						break
					if mask[x+i][z+h] != voxel_type:
						stop = true
						break
				if !stop:
					h += 1

			for dx in range(w):
				for dz in range(h):
					used[x+dx][z+dz] = true

			out.append({
				"x": x,
				"y": y, 
				"z": z, 
				"w": w, 
				"h": h, 
				"type": voxel_type,
				"face": FACE_TOP
			})

func _process(_delta):
	if player == null or world == null:
		return
		
	var cx = floori(player.voxel_position.x / float(ChunkData.SIZE))
	var cz = floori(player.voxel_position.z / float(ChunkData.SIZE))

	update_stream(cx, cz)
	
func update_stream(cx: int, cz: int):
	var needed := {}

	for z in range(cz - RENDER_DISTANCE, cz + RENDER_DISTANCE + 1):
		for x in range(cx - RENDER_DISTANCE, cx + RENDER_DISTANCE + 1):
			var key = Vector2i(x, z)
			needed[key] = true

			if not chunks.has(key):
				request_chunk(key)

	for key in chunks.keys():
		if not needed.has(key):
			chunks[key].queue_free()
			chunks.erase(key)
		
func _generate_chunk(data: ChunkData):
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			for y in range(ChunkData.HEIGHT):

				var wx = float(x + data.position.x * ChunkData.SIZE)
				var wz = float(z + data.position.y * ChunkData.SIZE) 
				var wy = float(y)

				var voxel_data = world.get_biome(wx, wy, wz)
				
				if voxel_data.has("is_air") and not voxel_data["is_air"]:
					var voxel_id = VoxelTypes.biome_to_voxel_id.get(
						voxel_data["name"],
						VoxelTypes.AIR
					)
					data.set_voxel(x, y, z, voxel_id)
				else:
					data.set_voxel(x, y, z, VoxelTypes.AIR)
					
func _on_chunk_ready(data: ChunkData, packed_mesh_arrays: Dictionary):
	if pending.has(data.position):                                              
			pending.erase(data.position)                                                             
	if chunks.has(data.position):                                                                                     
		return                                                                                              
	if not packed_mesh_arrays.has("count") or packed_mesh_arrays.count == 0:    
		print("DEBUG: No mesh data generated for chunk at position ", data.position, ", skipping ChunkView creation.")                                
		return                                                                  
	var view: ChunkView = CHUNK_VIEW_SCENE.instantiate()                        
	if view:                                                                    
		view.setup(data, packed_mesh_arrays) # Setup before adding to tree      
		add_child(view)                                                         
		chunks[data.position] = view                                                                                                       
	else:                                                                       
		print("ERROR: Failed to instantiate ChunkView for position: ", data.position)                                                                                              

func rebuild_chunks():
	for coord: Vector2i in chunks.keys():
		chunks[coord].emit_quads()
