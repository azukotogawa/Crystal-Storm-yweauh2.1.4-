extends Node3D
class_name ChunkView

@export var chunk_material: ShaderMaterial

@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var quads := []

func setup(data: ChunkData, mesh_data: Array):
	chunk_data = data
	quads = mesh_data
	emit_quads()

func emit_quads():
	for child in layer_container.get_children():
		child.queue_free()
		
	if quads.is_empty():
		return

	var chunk_offset_x = chunk_data.position.x * ChunkData.SIZE
	var chunk_offset_y = chunk_data.position.y * ChunkData.SIZE

	var layer_buckets := {}
	
	for q in quads:
		var screen_pos = IsoMath.voxel_to_screen(float(q.x + chunk_offset_x), float(q.y + chunk_offset_y), float(q.z))
		var depth_key = int(screen_pos.y + (float(q.z) * 2.0))
		
		if not layer_buckets.has(depth_key):
			layer_buckets[depth_key] = []
		layer_buckets[depth_key].append({"quad": q, "pos": screen_pos})



	for depth_key in layer_buckets.keys():
		var bucket_data = layer_buckets[depth_key]
		
		var mm_instance := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.instance_count = bucket_data.size()

		var mesh := QuadMesh.new()
		mesh.size = Vector2(1.0, 1.0)
		mm.mesh = mesh
		mm_instance.multimesh = mm
		
		if chunk_material:
			mm_instance.material_override = chunk_material
		
		layer_container.add_child(mm_instance)

		for i in range(bucket_data.size()):
			var item = bucket_data[i]
			var q = item["quad"]
			var screen_pos = item["pos"]

			var t = Transform3D.IDENTITY
			t.origin = Vector3(
				screen_pos.x / 64.0,
				-screen_pos.y / 64.0,
				0.0
			)
			mm.set_instance_transform(i, t)

			var voxel_type = q.type
			var coord = get_atlas_coord(voxel_type)
			mm.set_instance_custom_data(i, Color(coord.x / 255.0, coord.y / 255.0, 0.0, 0.0))

		mm_instance.sorting_offset = float(depth_key)

			
func get_atlas_coord(voxel_type: int) -> Vector2i:
	if voxel_type == VoxelTypes.AIR:
		return Vector2i(6, 0)
	return VoxelTypes.ATLAS_COORDS.get(voxel_type, Vector2i(6, 0))
