extends Node2D
class_name WallLine

var start_pos: Vector2
var end_pos: Vector2
var line_color: Color = Color.WHITE
var line_width: float = 2.5
var dash_length: float = 8.0
var gap_length: float = 6.0
var trim_edges: bool = false  # DODAJ to

func setup(from: Vector2, to: Vector2, color: Color = Color.WHITE, width: float = 2.5, trim: bool = false):
	start_pos = from
	end_pos = to
	line_color = color
	line_width = width
	trim_edges = trim  # DODAJ to
	queue_redraw()

func _draw():
	_draw_custom_dashed_line(start_pos, end_pos, line_color, line_width, dash_length, false, true)

func _draw_custom_dashed_line(from: Vector2, to: Vector2, color: Color, width: float = 2.5, dash: float = 8.0, cap_end: bool = false, antialiased: bool = true):
	var length = (to - from).length()
	var normal = (to - from).normalized()
	var gap = 6.0
	var dash_step = dash + gap
	
	# Skróć linię o 1 dash na każdym końcu
	var actual_start = from
	var actual_end = to
	
	if trim_edges:
		actual_start = from + normal * dash
		actual_end = to - normal * dash
		length = actual_start.distance_to(actual_end)
	
	if length < dash:
		draw_line(actual_start, actual_end, color, width, antialiased)
		return
	
	var segments = []
	var segment_start = actual_start
	var steps = length / dash_step
	
	# Zbierz wszystkie segmenty
	for i in range(int(steps) + 1):
		var segment_end = segment_start + normal * dash
		if segment_end.distance_to(actual_end) > dash:
			segments.append({"start": segment_start, "end": segment_end})
		else:
			# Ostatni segment - może być krótszy
			if segment_start.distance_to(actual_end) > 1:
				segments.append({"start": segment_start, "end": actual_end})
			break
		segment_start = segment_start + normal * dash_step
	
	# Rysuj segmenty
	for i in range(segments.size()):
		var seg = segments[i]
		var seg_start = seg.start
		var seg_end = seg.end
		
		# SKRÓĆ pierwszy dash o połowę od początku
		if i == 0 and trim_edges:
			seg_start = seg_start + normal * (dash * 0.4)
		
		# SKRÓĆ ostatni dash o połowę od końca
		if i == segments.size() - 1 and trim_edges:
			seg_end = seg_end - normal * (dash * 0.4)
		
		draw_line(seg_start, seg_end, color, width, antialiased)
