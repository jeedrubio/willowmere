class_name DayCycle
extends Node
## In-game calendar and clock. One in-game minute passes every 0.7 real seconds.

signal time_changed(day: int, minutes: int)
signal day_changed(day: int)
signal day_ended(day: int)

const START_MINUTES := 6 * 60
const END_MINUTES := 26 * 60 # 2:00 AM
const SECONDS_PER_GAME_MINUTE := 0.7

const COLOR_NIGHT := Color("#53617b")
const COLOR_DAWN := Color("#d0d5c6")
const COLOR_DAY := Color.WHITE
const COLOR_DUSK := Color("#edbd91")

var day := 1
var minutes := START_MINUTES
var running := false
var _elapsed := 0.0
var _day_end_emitted := false


func start() -> void:
	running = true
	time_changed.emit(day, minutes)


func sleep_until_morning() -> void:
	day += 1
	minutes = START_MINUTES
	_elapsed = 0.0
	_day_end_emitted = false
	running = true
	day_changed.emit(day)
	time_changed.emit(day, minutes)


func daylight_color() -> Color:
	var time_of_day := posmod(minutes, 24 * 60)
	if time_of_day < 5 * 60:
		return COLOR_NIGHT
	if time_of_day < 7 * 60:
		return COLOR_NIGHT.lerp(COLOR_DAWN, float(time_of_day - 5 * 60) / (2.0 * 60.0))
	if time_of_day < 8 * 60:
		return COLOR_DAWN.lerp(COLOR_DAY, float(time_of_day - 7 * 60) / 60.0)
	if time_of_day < 17 * 60:
		return COLOR_DAY
	if time_of_day < 19 * 60:
		return COLOR_DAY.lerp(COLOR_DUSK, float(time_of_day - 17 * 60) / (2.0 * 60.0))
	if time_of_day < 21 * 60:
		return COLOR_DUSK.lerp(COLOR_NIGHT, float(time_of_day - 19 * 60) / (2.0 * 60.0))
	return COLOR_NIGHT


func _process(delta: float) -> void:
	if not running or minutes >= END_MINUTES:
		return
	_elapsed += delta
	while _elapsed >= SECONDS_PER_GAME_MINUTE:
		_elapsed -= SECONDS_PER_GAME_MINUTE
		minutes += 1
		if minutes >= END_MINUTES:
			minutes = END_MINUTES
			_elapsed = 0.0
			running = false
		time_changed.emit(day, minutes)
		if minutes >= END_MINUTES and not _day_end_emitted:
			_day_end_emitted = true
			day_ended.emit(day)
			return
