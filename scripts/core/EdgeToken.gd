extends Node
## Edge TTS 新版 Sec-MS-GEC v2 令牌（微软混淆过的 SHA256 + CS64）。
## 纯离线计算，移植自 edge-tts 的 drm.py；token 每 5 分钟变化。

const TRUSTED := "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
const WIN_EPOCH := 11644473600.0
const MASK := 0xFFFFFFFF

const SHA_INITIAL := [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
const SHA_STATE := [0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A, 0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2]
const SHA_SCHEDULE := [0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564]
const SHA_ROUND_CONSTANTS := [0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA, 0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070, 0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2]
const SHA_BLOCK_CONSTANTS := [0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0xC9DC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA, 0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070, 0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2]
const SHA_ADJUSTMENT := 0xC9DC06A7
const SHA_SIGMA0_ADJUSTMENT := 0x059C0B80
const SHA_SIGMA1_ADJUSTMENT := 0x000B92C0
const CS64_COEFFICIENTS := [[0xE82E91B1, 0xB32700D0], [0x44DE24C6, 0x88DFF51D], [0x3BEB65BC, 0x29514038], [0xC89C5933, 0xB328CBDF], [0x8D1EC211, 0xD405B4D5], [0x314EF5D5, 0x26E55F3C], [0xE92491B1, 0x607801C6], [0xF0A5B9D5, 0x82B2C1FB], [0x06064CF3, 0xFA51A3DA], [0xDA79FA60, 0x207CC464], [0xBED20560, 0x3C3C74F3], [0x89F9C9F8, 0xD2D14B61], [0x35FA38C6, 0xBB04A2C1], [0xCB49E3C6, 0xC5626167]]
const CS64_FACTOR := 0x82893933
const CS64_ADJUSTMENT0 := 0xF2F90B1A
const CS64_ADJUSTMENT1 := 0x0B1A0000


static func _rotr(v: int, n: int) -> int:
	v &= MASK
	return ((v >> n) | (v << (32 - n))) & MASK


static func _rol16(v: int) -> int:
	v &= MASK
	return ((v << 16) | (v >> 16)) & MASK


## 32 位无符号乘法（避免 GDScript 64 位有符号溢出）
static func _mul32(a: int, b: int) -> int:
	var a0 := a & 0xFFFF
	var a1 := (a >> 16) & 0xFFFF
	var b0 := b & 0xFFFF
	var b1 := (b >> 16) & 0xFFFF
	var lo := a0 * b0
	var mid := (a0 * b1 + a1 * b0) & 0xFFFF
	return (lo + (mid << 16)) & MASK


static func _sigma0(v: int) -> int:
	return (_rotr(v, 7) ^ _rotr(v, 18) ^ ((v & MASK) >> 3)) & MASK


static func _sigma1(v: int) -> int:
	return (_rotr(v, 17) ^ _rotr(v, 19) ^ ((v & MASK) >> 10)) & MASK


static func _words_le4_even(data: PackedByteArray) -> Array:
	var padded := data.duplicate()
	while padded.size() % 4 != 0:
		padded.append(0)
	var words: Array = []
	var i := 0
	while i + 3 < padded.size():
		words.append(padded.decode_u32(i))
		i += 4
	if words.size() % 2 != 0:
		words.append(0)
	return words


static func _rounds(state: Array, words: Array, first_round: int = 0) -> Array:
	var a: int = state[0]
	var b: int = state[1]
	var c: int = state[2]
	var d: int = state[3]
	var e: int = state[4]
	var f: int = state[5]
	var g: int = state[6]
	var h: int = state[7]
	var constants: Array = SHA_BLOCK_CONSTANTS if first_round == 14 else SHA_ROUND_CONSTANTS
	for i in range(first_round, 64):
		var s1: int = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)
		var ch: int = g ^ (e & (f ^ g))
		var t1: int = (h + s1 + ch + int(constants[i]) + int(words[i])) & MASK
		var s0: int = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)
		var maj: int = (a & b) | (c & (a | b))
		var t2: int = (s0 + maj) & MASK
		h = g
		g = f
		f = e
		e = (d + t1) & MASK
		d = c
		c = b
		b = a
		a = (t1 + t2) & MASK
	return [a, b, c, d, e, f, g, h]


static func _expand(words: Array, first_word: int = 16) -> void:
	for i in range(first_word, 64):
		var x: int = words[i - 2]
		var y: int = words[i - 15]
		var sig1: int = _rotr(x, 17) ^ _rotr(x, 19) ^ ((x & MASK) >> 10)
		var sig0: int = _rotr(y, 7) ^ _rotr(y, 18) ^ ((y & MASK) >> 3)
		words.append((sig1 + int(words[i - 7]) + sig0 + int(words[i - 16])) & MASK)


static func _init_state(head: PackedByteArray) -> Array:
	var words: Array = []
	for i in range(14):
		words.append(0)
	var w14 := 0
	for i in range(3):
		w14 = (w14 << 8) | int(head[i])
	words.append(w14)
	var w15 := 0
	for i in range(3, 7):
		w15 = (w15 << 8) | int(head[i])
	words.append(w15)
	for index in range(16, 30):
		var value: int = int(SHA_SCHEDULE[index - 16])
		if index - 2 >= 14:
			var s1: int = _sigma1(int(words[index - 2]))
			if index == 16:
				s1 ^= SHA_SIGMA1_ADJUSTMENT
			value += s1
		if index - 7 >= 14:
			value += int(words[index - 7])
		if index - 15 >= 14:
			var s0: int = _sigma0(int(words[index - 15]))
			if index == 29:
				s0 ^= SHA_SIGMA0_ADJUSTMENT
			value += s0
		words.append(value & MASK)
	words.append((_sigma1(int(words[28])) + int(words[23]) + _sigma0(int(words[15])) + int(words[14])
		+ SHA_ADJUSTMENT - int(SHA_ROUND_CONSTANTS[14])) & MASK)
	_expand(words, 31)
	var working := _rounds(SHA_STATE, words, 14)
	var out: Array = []
	for i in range(8):
		out.append((int(SHA_INITIAL[i]) + int(working[i])) & MASK)
	return out


static func _sha_digest(data: PackedByteArray) -> PackedByteArray:
	var length: int = 57 + data.size()
	var padded := PackedByteArray()
	padded.append_array(data.slice(7))
	padded.append(0x80)
	var zeros: int = posmod(55 - length, 64)
	for i in range(zeros):
		padded.append(0)
	var bits: int = length * 8
	for sh in [56, 48, 40, 32, 24, 16, 8, 0]:
		padded.append((bits >> sh) & 0xFF)
	var state := _init_state(data.slice(0, 7))
	var offset := 0
	while offset < padded.size():
		var chunk := PackedByteArray()
		chunk.append_array(padded.slice(offset, offset + 64))
		var words: Array = []
		for i in range(16):
			var o: int = i * 4
			var w: int = (int(chunk[o]) << 24) | (int(chunk[o + 1]) << 16) | (int(chunk[o + 2]) << 8) | int(chunk[o + 3])
			words.append(w)
		_expand(words)
		var working := _rounds(state, words)
		var next_state: Array = []
		for i in range(8):
			next_state.append((int(state[i]) + int(working[i])) & MASK)
		state = next_state
		offset += 64
	var digest := PackedByteArray()
	for w in state:
		var v: int = int(w)
		digest.append((v >> 24) & 0xFF)
		digest.append((v >> 16) & 0xFF)
		digest.append((v >> 8) & 0xFF)
		digest.append(v & 0xFF)
	return digest


static func _cs64(data: PackedByteArray, digest: PackedByteArray) -> Array:
	var key_a: int = digest.decode_u32(0) | 1
	var key_b: int = digest.decode_u32(4) | 1
	var factors: Array = [_mul32(key_a, CS64_FACTOR), _mul32(key_b, CS64_FACTOR)]
	var terms: Array = []
	var offsets: Array = []
	for idx in range(CS64_COEFFICIENTS.size()):
		var pair: Array = CS64_COEFFICIENTS[idx]
		terms.append(_mul32(int(pair[0]), int(factors[idx % 2])))
		offsets.append(int(pair[1]))
	var raw := PackedByteArray()
	raw.append(0)
	raw.append_array(data)
	var words := _words_le4_even(raw)
	for index in range(words.size()):
		var word: int = int(words[index])
		var term := _mul32(word, key_a if index % 2 == 0 else key_b)
		var offset := _mul32(_rol16(word), 0xEF0569FB if index % 2 == 0 else 0xC31713DB)
		if index == 0:
			term = (term + _mul32(CS64_ADJUSTMENT0, int(factors[0]))) & MASK
			offset = (offset + CS64_ADJUSTMENT1) & MASK
		terms.append(term & MASK)
		offsets.append(offset & MASK)
	var swap_acc := 0
	var swap_last := 0
	var state := 0
	var acc := 0
	var i := 0
	while i < terms.size():
		var x: int = int(terms[i])
		var y: int = int(terms[i + 1])
		var t: int = _rol16((int(offsets[i]) + x) & MASK)
		var q: int = _mul32(t, 0x76F50F34)
		swap_acc = (swap_acc + _mul32(_rol16(q), 0xC3EFEA97) + q) & MASK
		t = _rol16((int(offsets[i + 1]) + y) & MASK)
		q = _mul32(t, 0x1881CE3C)
		swap_last = (_mul32(_rol16(q), 0x35BD1EC9) + q) & MASK
		swap_acc = (swap_acc + swap_last) & MASK
		state = (_mul32(state, key_a) + x) & MASK
		state = _mul32(_rol16(state), 0xCF98B111)
		state = _mul32(_rol16(state), 0x87085B9F)
		state = _mul32(_rol16(state), 0x12CEB96D)
		state = _mul32(_rol16(state), 0x257E1D83)
		acc = (acc + state) & MASK
		t = (_mul32(state, key_b) + y) & MASK
		t = _mul32(_rol16(t), 0xA27416F5)
		t = _mul32(_rol16(t), 0xD38396FF)
		state = _mul32(_rol16(_mul32(_rol16(t), 0x7C932B89)), 0xBFA49F69)
		acc = (acc + state) & MASK
		i += 2
	return [(swap_last ^ state) & MASK, (swap_acc ^ acc) & MASK]


## 生成 v2 token：<16位CS64>-<64位自定义SHA256>
static func token_for_unix(unix_ts: float) -> String:
	var ticks: float = unix_ts + WIN_EPOCH
	ticks -= fmod(ticks, 300.0)
	ticks *= 10000000.0
	var s: String = "%.0f" % ticks
	s += TRUSTED
	var data: PackedByteArray = s.to_utf8_buffer()
	var digest := _sha_digest(data)
	var words := _cs64(data, digest)
	var cs := ""
	for w in words:
		var v: int = int(w)
		cs += "%02X%02X%02X%02X" % [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]
	var sh := ""
	for b in digest:
		sh += "%02X" % int(b)
	return cs + "-" + sh


static func current_token() -> String:
	return token_for_unix(Time.get_unix_time_from_system())
