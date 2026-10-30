class_name Skill
extends Resource

@export var skill_name: String = ""
@export var cooldown: float = 0
@export var mana_cost: int = 0
@export var phy_damage: float = 0
@export var damage: float = 0
@export var bonus_ratio: float = 0
@export var mag_damage: float = 0
@export var radius: float = 0.0
@export var cast_range: float = 0
@export var type: int = 0               # 0=目标,1=范围,2=增益,3=线性,4=位移,5=多段,6=护盾
@export var phy_bonus_ratio: float = 0
@export var mag_bonus_ratio: float = 0      # 加成系数 (AD/AP)
@export var restore: int = 0  
@export var restore_bonus: int = 0  
@export var duration: float = 0.0       # 增益/护盾持续
@export var cast_time: float = 0.0      # 施法前摇（秒）；0=按 Hero 默认前摇表（type 决定），>0 覆盖
@export var cd_bonus: float = 0       # 增益/护盾持续
@export var power_bonus: float = 0  
@export var is_channeling: bool = false # 引导类
@export var projectile_speed: float = 12.0
@export var applies_slow: float = 0.0   # 减速百分比
@export var slow_duration: float = 0.0
@export var applies_stun: float = 0.0   # 眩晕时长
@export var applies_knockup: float = 0.0 # 击飞时长
@export var bullet_range: float = 0.0     # 线性技能子弹最远飞行距离
@export var self_displacement: float = 0.0 # 自身位移距离
@export var shield_amount: float = 0.0  # 护盾量
  # 增益持续
