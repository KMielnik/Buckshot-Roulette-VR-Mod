extends Node3D

var voice: Label
var title_source: Label
var detail_source: Label
var blocker: ColorRect
var interaction: Node
var dialogue: Label3D
var description: Label3D
var active := false
var hovered: Node
var indicator: Node


func mount(scene: Node, desk: Transform3D, units: float) -> bool:
	var speaker := scene.get_node_or_null("standalone managers/dialogue manager")
	var info := scene.get_node_or_null("standalone managers/description manager")
	var death := scene.get_node_or_null("standalone managers/death manager")
	if speaker == null or info == null or death == null or units <= 0:
		return false
	voice = speaker.get("dialogueUI") as Label
	var labels = info.get("uiArray")
	if not labels is Array or labels.size() != 4:
		return false
	title_source = labels[1] as Label
	detail_source = labels[3] as Label
	blocker = death.get("viewblocker") as ColorRect
	interaction = info.get("interaction") as Node
	if voice == null or title_source == null or detail_source == null or blocker == null or interaction == null:
		return false
	top_level = true
	global_transform = desk
	dialogue = Label3D.new()
	description = Label3D.new()
	# Both cards stay at the desk. Dialogue grows upward above the face; the
	# description grows downward at the player's right, beside the play area.
	_setup_label(dialogue, voice, Vector3(0, 0.33, -1.65), 1350, units)
	dialogue.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_setup_label(description, detail_source, Vector3(0.32, -0.16, -1.25), 750, units)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	process_priority = 10
	set_active(false)
	return true


func _setup_label(label: Label3D, source: Label, offset_metres: Vector3, width_pixels: int, units: float) -> void:
	label.font_size = 44
	label.font = source.get_theme_font(&"font")
	label.pixel_size = 0.00088 * units
	label.position = offset_metres * units
	label.width = width_pixels
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(1.0, 0.94, 0.83)
	label.outline_modulate = Color(0.045, 0.028, 0.023)
	label.outline_size = 7
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)


func set_active(value: bool) -> void:
	active = value
	if not active:
		hide()


func _process(_delta: float) -> void:
	if not active or not is_instance_valid(voice) or not is_instance_valid(blocker) or blocker.is_visible_in_tree():
		hide()
		return
	show()
	var message := voice.tr(voice.text)
	var count := voice.visible_characters
	dialogue.visible = voice.is_visible_in_tree() and count != 0 and not message.is_empty()
	if dialogue.visible:
		dialogue.text = message if count < 0 else message.left(count)
	var target = interaction.get("activeParent")
	if not is_instance_valid(target):
		hovered = null
		indicator = null
	elif hovered != target:
		hovered = target
		indicator = null
		for child in hovered.get_children():
			if child.has_method("BeginPickup") and child.get("collider") == hovered:
				indicator = child
				break
	var branch = interaction.get("activeInteractionBranch")
	description.visible = (is_instance_valid(indicator) and is_instance_valid(branch)
			and branch.get_parent() == hovered and branch.get("interactionAllowed") and not branch.get("interactionInvalid")
			and indicator.get("interactionAllowed") and not indicator.get("interactionInvalid")
			and title_source.is_visible_in_tree() and detail_source.is_visible_in_tree()
			and title_source.modulate.a > 0.01 and title_source.text == indicator.get("itemName")
			and detail_source.text == indicator.get("itemDescription"))
	if description.visible:
		description.text = title_source.tr(title_source.text) + "\n" + detail_source.tr(detail_source.text)
		description.modulate.a = title_source.modulate.a
		description.outline_modulate.a = title_source.modulate.a


func unmount() -> void:
	set_active(false)
	set_process(false)
