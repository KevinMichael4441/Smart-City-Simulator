class_name Metrics
extends RefCounted

const CAP := 1080

var _data: Dictionary = {}

func declare(names: Array) -> void:
	for n in names:
		if not _data.has(n):
			_data[n] = PackedFloat32Array()

func push(values: Dictionary) -> void:
	for n in _data.keys():
		var a: PackedFloat32Array = _data[n]
		var v: float = float(values.get(n, a[-1] if a.size() > 0 else 0.0))
		a.append(v)
		if a.size() > CAP:
			a.remove_at(0)
		_data[n] = a

func series(n: String) -> PackedFloat32Array:
	return _data.get(n, PackedFloat32Array())

func latest(n: String, fallback := 0.0) -> float:
	var a: PackedFloat32Array = _data.get(n, PackedFloat32Array())
	return a[-1] if a.size() > 0 else fallback

func window_avg(n: String, count: int) -> float:
	var a: PackedFloat32Array = _data.get(n, PackedFloat32Array())
	if a.is_empty():
		return 0.0
	var start: int = max(0, a.size() - count)
	var total := 0.0
	for i in range(start, a.size()):
		total += a[i]
	return total / float(a.size() - start)
