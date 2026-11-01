extends Node
## Windows 本地 SAPI 兜底朗读：用子进程调用 System.Speech（绕过 Godot 内置 WinRT TTS 在导出包的崩溃问题）。
## 不依赖网络，读中文可靠（系统装了中文语音包即可，如 Huihui/Yaoyao/Kangkang）。

var _pid := -1


func available() -> bool:
	return OS.has_feature("windows")


## rate: -5..5（负数更慢）；pitch 暂不支持（System.Speech 的 SSML pitch 支持有限）
func speak(text: String, rate: int = 0, female: bool = false) -> bool:
	if not available():
		return false
	var t := text.replace("'", "''").replace("\"", "''")
	var r := clampi(rate, -6, 6)
	# 按英雄性别选系统中文音色（SAPI 优先匹配 Gender；找不到则保持默认）
	var gender := "Female" if female else "Male"
	var script := "Add-Type -AssemblyName System.Speech;$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;$v=@($s.GetInstalledVoices())|Where-Object{$_.VoiceInfo.Culture.Name -like 'zh*' -and $_.VoiceInfo.Gender -eq '%s'}|Select-Object -First 1;if($v){$s.SelectVoice($v.VoiceInfo.Name)};$s.Rate=%d;$s.Speak('%s');$s.Dispose()" % [gender, r, t]
	# PowerShell -EncodedCommand 要求 UTF-16LE 的 Base64
	var bytes := script.to_utf16_buffer()
	var b64 := Marshalls.raw_to_base64(bytes)
	var pid := OS.create_process("powershell.exe", [
		"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", b64
	])
	if pid <= 0:
		print("[SAPI] create_process failed")
		return false
	_pid = pid
	return true
