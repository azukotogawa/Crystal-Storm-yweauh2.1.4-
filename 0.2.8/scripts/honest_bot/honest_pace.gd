extends RefCounted

const GAP := 0.15
const PRE_PAUSE := 1.0
const RESULT_HOLD := 2.5
const SETTLE := 1.0
const MIN_CHAPTER := 4.0


static func short_feature(body: String) -> String:
	for raw in body.split("\n", false):
		var line := raw.strip_edges()
		if line == "":
			continue
		var parts := line.split(" ", false)
		if parts.size() < 3:
			return str(parts[0]) if parts.size() > 0 else "?"
		var span := float(parts[parts.size() - 1]) - float(parts[parts.size() - 2])
		if span < MIN_CHAPTER:
			return str(parts[0])
	return ""


static func gap_fault(hands: RefCounted) -> String:
	if hands == null:
		return "no input"
	hands.pace_presses = true
	hands._since_press = GAP
	if not hands.pulse("attack"):
		return "first press blocked"
	if hands.pulse("jump"):
		return "same-frame chain"
	hands.advance_pace(GAP - 0.02)
	if hands.pulse("jump"):
		return "gap short"
	hands.advance_pace(0.03)
	if not hands.pulse("jump"):
		return "gap not open"
	if hands.pulse("pause"):
		return "second chain"
	hands.begin_tick()
	hands.release_all()
	return ""
