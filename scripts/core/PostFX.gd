extends CanvasLayer
## 全屏后处理层（autoload PostFX）：轻调色/暗角/受击边缘红晕/死亡去饱和/受击色差。
## layer=0：在 3D 之上、UI（CanvasLayer 默认 layer 1 及联机 HUD 的 20+）之下，不影响 HUD/面板。
## 只做表现，不参与战斗逻辑；单机与联机共用。

const SHADER := preload("res://scripts/core/postfx.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial
var _dmg := 0.0
var _dead := 0.0
var _ab := 0.0

func _ready() -> void:
	layer = UiKit.LAYER_POSTFX   # 3D 之上、世界血条(LAYER_WORLD=8)/主 HUD(20) 之下；分层表见 UiKit
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "PostFXRect"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)
	_push()

## 受击：屏幕边缘红晕脉冲（strength 0..1，自动衰减）
func damage(strength: float = 0.7, ab: float = 0.35) -> void:
	_dmg = maxf(_dmg, clampf(strength, 0.0, 1.0))
	_ab = maxf(_ab, clampf(ab, 0.0, 1.0) * _dmg)
	_push()

## 阵亡压暗/去饱和（复活后由调用方复位 false）
func set_dead(on: bool) -> void:
	var v := 1.0 if on else 0.0
	if is_equal_approx(v, _dead):
		return
	_dead = v
	_push()

func _process(delta: float) -> void:
	if _dmg <= 0.001 and _ab <= 0.001:
		return
	_dmg = maxf(0.0, _dmg - delta * 2.4)
	_ab = maxf(0.0, _ab - delta * 3.0)
	_push()

func _push() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("damage", _dmg)
	_mat.set_shader_parameter("dead", _dead)
	_mat.set_shader_parameter("aberration", _ab)
