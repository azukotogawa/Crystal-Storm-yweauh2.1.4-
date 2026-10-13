class_name ChunkStreamLifecycle
extends RefCounted
## Explicit chunk streaming lifecycle states (stream path only).


const UNLOADED := "UNLOADED"
const REQUESTED := "REQUESTED"
const ALLOCATED := "ALLOCATED"
const HEIGHT_GENERATED := "HEIGHT_GENERATED"
const MESH_GENERATED := "MESH_GENERATED"
const QUEUED_FOR_UPLOAD := "QUEUED_FOR_UPLOAD"
const UPLOADING := "UPLOADING"
const UPLOADED := "UPLOADED"
const ACTIVE := "ACTIVE"
const IDLE := "IDLE"
const UNLOADING := "UNLOADING"