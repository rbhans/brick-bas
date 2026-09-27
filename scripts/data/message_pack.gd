class_name MessagePackCodec
extends RefCounted

const MAX_DEPTH := 32
const MAX_COLLECTION := 10000
const MAX_BYTES := 1048576

static func encode(value: Variant) -> PackedByteArray:
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	if not _write(stream, value, 0): return PackedByteArray()
	return stream.data_array

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return {"ok": false, "error": "MessagePack frame size is invalid."}
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	stream.data_array = bytes
	var result := _read(stream, 0)
	if not result.ok: return result
	if stream.get_available_bytes() != 0:
		return {"ok": false, "error": "MessagePack frame has trailing bytes."}
	return result

static func _write(stream: StreamPeerBuffer, value: Variant, depth: int) -> bool:
	if depth > MAX_DEPTH: return false
	match typeof(value):
		TYPE_NIL: stream.put_u8(0xc0)
		TYPE_BOOL: stream.put_u8(0xc3 if value else 0xc2)
		TYPE_INT: _write_int(stream, int(value))
		TYPE_FLOAT:
			stream.put_u8(0xcb)
			stream.put_double(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			var bytes := String(value).to_utf8_buffer()
			if bytes.size() > MAX_BYTES: return false
			_write_length(stream, bytes.size(), 0xa0, 31, 0xd9, 0xda, 0xdb)
			stream.put_data(bytes)
		TYPE_PACKED_BYTE_ARRAY:
			var bytes: PackedByteArray = value
			if bytes.size() > MAX_BYTES: return false
			if bytes.size() <= 0xff: stream.put_u8(0xc4); stream.put_u8(bytes.size())
			elif bytes.size() <= 0xffff: stream.put_u8(0xc5); stream.put_u16(bytes.size())
			else: stream.put_u8(0xc6); stream.put_u32(bytes.size())
			stream.put_data(bytes)
		TYPE_ARRAY:
			if value.size() > MAX_COLLECTION: return false
			_write_collection_header(stream, value.size(), 0x90, 15, 0xdc, 0xdd)
			for entry in value:
				if not _write(stream, entry, depth + 1): return false
		TYPE_DICTIONARY:
			if value.size() > MAX_COLLECTION: return false
			_write_collection_header(stream, value.size(), 0x80, 15, 0xde, 0xdf)
			var keys: Array = value.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
			for key in keys:
				if not _write(stream, String(key), depth + 1) or not _write(stream, value[key], depth + 1): return false
		_: return false
	return true

static func _write_int(stream: StreamPeerBuffer, value: int) -> void:
	if value >= 0 and value <= 0x7f: stream.put_u8(value)
	elif value >= -32 and value < 0: stream.put_u8(value & 0xff)
	elif value >= 0 and value <= 0xff: stream.put_u8(0xcc); stream.put_u8(value)
	elif value >= 0 and value <= 0xffff: stream.put_u8(0xcd); stream.put_u16(value)
	elif value >= 0 and value <= 0xffffffff: stream.put_u8(0xce); stream.put_u32(value)
	elif value >= 0: stream.put_u8(0xcf); stream.put_u64(value)
	elif value >= -128: stream.put_u8(0xd0); stream.put_8(value)
	elif value >= -32768: stream.put_u8(0xd1); stream.put_16(value)
	elif value >= -2147483648: stream.put_u8(0xd2); stream.put_32(value)
	else: stream.put_u8(0xd3); stream.put_64(value)

static func _write_length(stream: StreamPeerBuffer, length: int, fix: int, fix_max: int, byte_code: int, short_code: int, long_code: int) -> void:
	if length <= fix_max: stream.put_u8(fix | length)
	elif length <= 0xff: stream.put_u8(byte_code); stream.put_u8(length)
	elif length <= 0xffff: stream.put_u8(short_code); stream.put_u16(length)
	else: stream.put_u8(long_code); stream.put_u32(length)

static func _write_collection_header(stream: StreamPeerBuffer, length: int, fix: int, fix_max: int, short_code: int, long_code: int) -> void:
	if length <= fix_max: stream.put_u8(fix | length)
	elif length <= 0xffff: stream.put_u8(short_code); stream.put_u16(length)
	else: stream.put_u8(long_code); stream.put_u32(length)

static func _read(stream: StreamPeerBuffer, depth: int) -> Dictionary:
	if depth > MAX_DEPTH or stream.get_available_bytes() < 1: return {"ok": false, "error": "Truncated MessagePack frame."}
	var code := stream.get_u8()
	if code <= 0x7f: return {"ok": true, "value": code}
	if code >= 0xe0: return {"ok": true, "value": code - 256}
	if code >= 0xa0 and code <= 0xbf: return _read_string(stream, code & 0x1f)
	if code >= 0x90 and code <= 0x9f: return _read_array(stream, code & 0x0f, depth)
	if code >= 0x80 and code <= 0x8f: return _read_map(stream, code & 0x0f, depth)
	match code:
		0xc0: return {"ok": true, "value": null}
		0xc2: return {"ok": true, "value": false}
		0xc3: return {"ok": true, "value": true}
		0xcc: return _read_number(stream, 1, func() -> int: return stream.get_u8())
		0xcd: return _read_number(stream, 2, func() -> int: return stream.get_u16())
		0xce: return _read_number(stream, 4, func() -> int: return stream.get_u32())
		0xcf: return _read_number(stream, 8, func() -> int: return stream.get_u64())
		0xd0: return _read_number(stream, 1, func() -> int: return stream.get_8())
		0xd1: return _read_number(stream, 2, func() -> int: return stream.get_16())
		0xd2: return _read_number(stream, 4, func() -> int: return stream.get_32())
		0xd3: return _read_number(stream, 8, func() -> int: return stream.get_64())
		0xcb: return _read_number(stream, 8, func() -> float: return stream.get_double())
		0xd9: return _read_string(stream, stream.get_u8()) if stream.get_available_bytes() >= 1 else {"ok": false, "error": "Truncated string length."}
		0xda: return _read_string(stream, stream.get_u16()) if stream.get_available_bytes() >= 2 else {"ok": false, "error": "Truncated string length."}
		0xdb: return _read_string(stream, stream.get_u32()) if stream.get_available_bytes() >= 4 else {"ok": false, "error": "Truncated string length."}
		0xc4: return _read_binary(stream, stream.get_u8()) if stream.get_available_bytes() >= 1 else {"ok": false, "error": "Truncated binary length."}
		0xc5: return _read_binary(stream, stream.get_u16()) if stream.get_available_bytes() >= 2 else {"ok": false, "error": "Truncated binary length."}
		0xc6: return _read_binary(stream, stream.get_u32()) if stream.get_available_bytes() >= 4 else {"ok": false, "error": "Truncated binary length."}
		0xdc: return _read_array(stream, stream.get_u16(), depth) if stream.get_available_bytes() >= 2 else {"ok": false, "error": "Truncated array length."}
		0xdd: return _read_array(stream, stream.get_u32(), depth) if stream.get_available_bytes() >= 4 else {"ok": false, "error": "Truncated array length."}
		0xde: return _read_map(stream, stream.get_u16(), depth) if stream.get_available_bytes() >= 2 else {"ok": false, "error": "Truncated map length."}
		0xdf: return _read_map(stream, stream.get_u32(), depth) if stream.get_available_bytes() >= 4 else {"ok": false, "error": "Truncated map length."}
	return {"ok": false, "error": "Unsupported MessagePack type 0x%02x." % code}

static func _read_number(stream: StreamPeerBuffer, required: int, reader: Callable) -> Dictionary:
	if stream.get_available_bytes() < required: return {"ok": false, "error": "Truncated MessagePack number."}
	return {"ok": true, "value": reader.call()}

static func _read_string(stream: StreamPeerBuffer, length: int) -> Dictionary:
	var bytes := _take(stream, length)
	if bytes.size() != length: return {"ok": false, "error": "Truncated MessagePack string."}
	return {"ok": true, "value": bytes.get_string_from_utf8()}

static func _read_binary(stream: StreamPeerBuffer, length: int) -> Dictionary:
	var bytes := _take(stream, length)
	return {"ok": bytes.size() == length, "value": bytes, "error": "Truncated MessagePack binary." if bytes.size() != length else ""}

static func _read_array(stream: StreamPeerBuffer, length: int, depth: int) -> Dictionary:
	if length > MAX_COLLECTION: return {"ok": false, "error": "MessagePack array exceeds limit."}
	var value: Array = []
	for _index in range(length):
		var entry := _read(stream, depth + 1)
		if not entry.ok: return entry
		value.append(entry.value)
	return {"ok": true, "value": value}

static func _read_map(stream: StreamPeerBuffer, length: int, depth: int) -> Dictionary:
	if length > MAX_COLLECTION: return {"ok": false, "error": "MessagePack map exceeds limit."}
	var value: Dictionary = {}
	for _index in range(length):
		var key := _read(stream, depth + 1)
		if not key.ok: return key
		if not key.value is String: return {"ok": false, "error": "MessagePack map keys must be strings."}
		var entry := _read(stream, depth + 1)
		if not entry.ok: return entry
		value[key.value] = entry.value
	return {"ok": true, "value": value}

static func _take(stream: StreamPeerBuffer, length: int) -> PackedByteArray:
	if length < 0 or length > MAX_BYTES or stream.get_available_bytes() < length: return PackedByteArray()
	return stream.get_data(length)[1]
