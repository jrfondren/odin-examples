package main

import "core:math"
sin, cos :: math.sin, math.cos
import rl "vendor:raylib"
import "core:c"
import "core:fmt"

when #config(audio, true) {
	foreign import sun "./sunvox.so"
	foreign sun {
		sv_init :: proc(config: cstring, freq, channels: c.int, flags: u32) -> c.int ---
		sv_deinit :: proc() -> c.int ---
		sv_open_slot :: proc(slot: c.int) -> c.int ---
		sv_close_slot :: proc(slot: c.int) -> c.int ---
		sv_load :: proc(slot: c.int, name: cstring) -> c.int ---
		sv_volume :: proc(slot, vol: c.int) -> c.int ---
		sv_get_song_name :: proc(slot: c.int) -> cstring ---
		sv_play_from_beginning :: proc(slot: c.int) -> c.int ---
		sv_find_module :: proc(slot: c.int, name: cstring) -> c.int ---
		sv_send_event :: proc(slot, track_num, note, vel, module, ctl, ctl_val: c.int) -> c.int ---
		sv_pause :: proc(slot: c.int) -> c.int ---
		sv_resume :: proc(slot: c.int) -> c.int ---
	}
}

PLAYER_BASE_SIZE :: 20.0
PLAYER_SPEED :: 6.0
PLAYER_MAX_SHOOTS :: 10

METEORS_SPEED :: 2
MAX_BIG_METEORS :: 4
MAX_MEDIUM_METEORS :: 8
MAX_SMALL_METEORS :: 16

screenWidth, screenHeight :: 800, 450

Keys :: rl.KeyboardKey
Color :: rl.Color

Player :: struct {
	position, speed:        rl.Vector2,
	acceleration, rotation: f32,
	collider:               [3]f32,
	color:                  Color,
}

Meteor :: struct {
	position, speed: rl.Vector2,
	radius:          f32,
	active:          bool,
	color:           Color,
}

Shoot :: struct {
	position, speed: rl.Vector2,
	radius:          f32,
	active:          bool,
	color:           Color,
	rotation:        f32,
	lifeSpawn:       int,
}

gameOver, pause, victory: bool
shipHeight: f32
player: Player
shoot: [PLAYER_MAX_SHOOTS]Shoot
bigMeteor: [MAX_BIG_METEORS]Meteor
mediumMeteor: [MAX_MEDIUM_METEORS]Meteor
smallMeteor: [MAX_SMALL_METEORS]Meteor
midMeteorsCount, smallMeteorsCount, destroyedMeteorsCount: int
DrumSynth: c.int
ShootNote, BreakNote: c.int

Note :: enum {
	C,
	Cs,
	D,
	Ds,
	E,
	F,
	Fs,
	G,
	Gs,
	A,
	As,
	B,
}

note :: proc(note: Note, octave: int) -> c.int {
	return c.int(octave * 12 + 2 + int(note))
}

kicksound :: proc() {
	when #config(audio, true) {
		sv_send_event(0, 0, ShootNote, 129, DrumSynth + 1, 0, 0)
	}
}

breaksound :: proc() {
	when #config(audio, true) {
		sv_send_event(0, 0, BreakNote, 129, DrumSynth + 1, 0, 0)
	}
}

main :: proc() {
	// init audio
	ShootNote = note(.C, 9)
	BreakNote = note(.Gs, 7)

	when #config(audio, true) {
		if sv_init("", 44100, 2, 0) < 0 {
			fmt.eprintln("failed to init sunvox")
			return
		}
		defer sv_deinit()
		sv_open_slot(0)
		defer sv_close_slot(0)
		if sv_load(0, "asteroids.sunvox") != 0 {
			fmt.eprintln("failed to load bgm")
			return
		}
		fmt.println("loaded bgm:", sv_get_song_name(0))
		DrumSynth = sv_find_module(0, "DrumSynth2")
		if DrumSynth < 0 {
			fmt.eprintln("failed to find DrumSynth!")
			return
		}
	}

	// init graphics
	rl.InitWindow(screenWidth, screenHeight, "classic game: asteroids")
	defer rl.CloseWindow()

	InitGame()
	defer UnloadGame()
	rl.SetTargetFPS(60)

	// start playing
	when #config(audio, true) do sv_play_from_beginning(0)
	for !rl.WindowShouldClose() do UpdateDrawFrame()
}

InitGame :: proc() {
	posx, posy: i32
	velx, vely: i32
	victory = false
	pause = false

	shipHeight = (PLAYER_BASE_SIZE / 2) / math.tan(f32(20 * rl.DEG2RAD))

	// Initialize player
	player.position = {screenWidth / 2, screenHeight / 2 - shipHeight / 2}
	player.speed = {}
	player.acceleration = 0
	player.rotation = 0
	player.collider = {
		player.position.x + sin(f32(player.rotation * rl.DEG2RAD)) * shipHeight / 2.5,
		player.position.y - cos(f32(player.rotation * rl.DEG2RAD)) * shipHeight / 2.5,
		12,
	}
	player.color = rl.LIGHTGRAY

	destroyedMeteorsCount = 0


	// Initialize shoot
	for i in 0 ..< PLAYER_MAX_SHOOTS {
		shoot[i] = Shoot {
			radius = 2,
			color  = rl.WHITE,
		}
	}

	for i in 0 ..< MAX_BIG_METEORS {
		for {
			posx = rl.GetRandomValue(0, screenWidth)
			if !(posx > screenWidth / 2 - 150 && posx < screenWidth / 2 + 150) {
				break
			}
		}
		for {
			posy = rl.GetRandomValue(0, screenHeight)
			if !(posy > screenHeight / 2 - 150 && posy < screenHeight / 2 + 150) {
				break
			}
		}
		bigMeteor[i].position = {f32(posx), f32(posy)}

		for {
			velx = rl.GetRandomValue(-METEORS_SPEED, METEORS_SPEED)
			vely = rl.GetRandomValue(-METEORS_SPEED, METEORS_SPEED)
			if velx != 0 && vely != 0 do break
		}
		bigMeteor[i].speed = {f32(velx), f32(vely)}
		bigMeteor[i].radius = 40
		bigMeteor[i].active = true
		bigMeteor[i].color = rl.BLUE
	}

	for i in 0 ..< MAX_MEDIUM_METEORS {
		mediumMeteor[i].position = {-100, -100}
		mediumMeteor[i].speed = {}
		mediumMeteor[i].radius = 20
		mediumMeteor[i].active = false
		mediumMeteor[i].color = rl.BLUE
	}

	for i in 0 ..< MAX_SMALL_METEORS {
		smallMeteor[i].position = {-100, -100}
		smallMeteor[i].speed = {}
		smallMeteor[i].radius = 10
		smallMeteor[i].active = false
		smallMeteor[i].color = rl.BLUE
	}

	midMeteorsCount = 0
	smallMeteorsCount = 0
	when #config(audio, true) do sv_volume(0, 256 / 2)
}

UpdateGame :: proc() {
	if gameOver {
		if rl.IsKeyPressed(Keys.ENTER) {
			InitGame()
			gameOver = false
		}
		return
	}
	if rl.IsKeyPressed(Keys.P) {
		pause = !pause
		if pause {
			when #config(audio, true) do sv_pause(0)
		} else {
			when #config(audio, true) do sv_resume(0)
		}
	}
	if pause do return

	if rl.IsKeyDown(Keys.LEFT) do player.rotation -= 5
	if rl.IsKeyDown(Keys.RIGHT) do player.rotation += 5

	player.speed.x = sin(player.rotation * rl.DEG2RAD) * PLAYER_SPEED
	player.speed.y = cos(player.rotation * rl.DEG2RAD) * PLAYER_SPEED

	if rl.IsKeyDown(Keys.UP) {
		if player.acceleration < 1 do player.acceleration += 0.04
	} else {
		if player.acceleration > 0 {player.acceleration -= 0.02
		} else if player.acceleration < 0 {player.acceleration = 0}
	}
	if rl.IsKeyDown(Keys.DOWN) {
		if player.acceleration >
		   0 {player.acceleration -= 0.04} else if player.acceleration < 0 {player.acceleration = 0}
	}

	// Player logic: movement
	player.position.x += player.speed.x * player.acceleration
	player.position.y -= player.speed.y * player.acceleration

	// Collision logic: player vs. walls
	if player.position.x >
	   screenWidth +
		   shipHeight {player.position.x = -shipHeight} else if player.position.x < -shipHeight {player.position.x = screenWidth + shipHeight}
	if player.position.y >
	   screenHeight +
		   shipHeight {player.position.y = -shipHeight} else if player.position.y < -shipHeight {player.position.y = screenHeight + shipHeight}

	// Player shoot logic
	if rl.IsKeyPressed(Keys.SPACE) {
		for i in 0 ..< PLAYER_MAX_SHOOTS {
			if shoot[i].active do continue
			shoot[i].active = true
			shoot[i].position = {
				player.position.x + sin(player.rotation * rl.DEG2RAD) * shipHeight,
				player.position.y - cos(player.rotation * rl.DEG2RAD) * shipHeight,
			}
			shoot[i].speed.x = 1.5 * sin(player.rotation * rl.DEG2RAD) * PLAYER_SPEED
			shoot[i].speed.y = 1.5 * cos(player.rotation * rl.DEG2RAD) * PLAYER_SPEED
			shoot[i].rotation = player.rotation
			kicksound()
			break
		}
	}

	// Shoot life timer
	for i in 0 ..< PLAYER_MAX_SHOOTS {
		if shoot[i].active do shoot[i].lifeSpawn += 1
	}

	// Shot logic
	for i in 0 ..< PLAYER_MAX_SHOOTS {

		if !shoot[i].active do continue
		shoot[i].position.x += shoot[i].speed.x
		shoot[i].position.y -= shoot[i].speed.y

		// Collision logic: shoot vs. walls
		if shoot[i].position.x > screenWidth + shoot[i].radius {
			shoot[i].active = false
			shoot[i].lifeSpawn = 0
		} else if shoot[i].position.x < 0 - shoot[i].radius {
			shoot[i].active = false
			shoot[i].lifeSpawn = 0
		}
		if shoot[i].position.y > screenHeight + shoot[i].radius {
			shoot[i].active = false
			shoot[i].lifeSpawn = 0
		} else if shoot[i].position.y < 0 - shoot[i].radius {
			shoot[i].active = false
			shoot[i].lifeSpawn = 0
		}

		if shoot[i].lifeSpawn >= 60 {
			shoot[i] = {}
		}
	}

	// Collision logic: player vs. meteors
	player.collider = {
		player.position.x + sin(player.rotation * rl.DEG2RAD) * (shipHeight / 2.5),
		player.position.y - cos(player.rotation * rl.DEG2RAD) * (shipHeight / 2.5),
		12,
	}

	for i in 0 ..< MAX_BIG_METEORS {
		if !bigMeteor[i].active do continue
		if rl.CheckCollisionCircles(
			player.collider.xy,
			player.collider.z,
			bigMeteor[i].position,
			bigMeteor[i].radius,
		) {
			gameOver = true
		}
	}
	for i in 0 ..< MAX_MEDIUM_METEORS {
		if !mediumMeteor[i].active do continue
		if rl.CheckCollisionCircles(
			player.collider.xy,
			player.collider.z,
			mediumMeteor[i].position,
			mediumMeteor[i].radius,
		) {
			gameOver = true
		}
	}
	for i in 0 ..< MAX_SMALL_METEORS {
		if !smallMeteor[i].active do continue
		if rl.CheckCollisionCircles(
			player.collider.xy,
			player.collider.z,
			smallMeteor[i].position,
			smallMeteor[i].radius,
		) {
			gameOver = true
		}
	}

	// Meteors logic
	for i in 0 ..< MAX_BIG_METEORS {
		if !bigMeteor[i].active do continue
		// Movement
		bigMeteor[i].position += bigMeteor[i].speed

		// Collision logic: meteor vs. wall
		if bigMeteor[
			   i \
		   ].position.x >
		   screenWidth +
			   bigMeteor[
					   i \
				   ].radius {bigMeteor[i].position.x = -bigMeteor[i].radius} else if bigMeteor[i].position.x < 0 - bigMeteor[i].radius {bigMeteor[i].position.x = screenWidth + bigMeteor[i].radius}
		if bigMeteor[
			   i \
		   ].position.y >
		   screenHeight +
			   bigMeteor[
					   i \
				   ].radius {bigMeteor[i].position.y = -bigMeteor[i].radius} else if bigMeteor[i].position.y < 0 - bigMeteor[i].radius {bigMeteor[i].position.y = screenHeight + bigMeteor[i].radius}
	}
	for i in 0 ..< MAX_MEDIUM_METEORS {
		if !mediumMeteor[i].active do continue
		// Movement
		mediumMeteor[i].position += mediumMeteor[i].speed

		// Collision logic: meteor vs. wall
		if mediumMeteor[
			   i \
		   ].position.x >
		   screenWidth +
			   mediumMeteor[
					   i \
				   ].radius {mediumMeteor[i].position.x = -mediumMeteor[i].radius} else if mediumMeteor[i].position.x < 0 - mediumMeteor[i].radius {mediumMeteor[i].position.x = screenWidth + mediumMeteor[i].radius}
		if mediumMeteor[
			   i \
		   ].position.y >
		   screenHeight +
			   mediumMeteor[
					   i \
				   ].radius {mediumMeteor[i].position.y = -mediumMeteor[i].radius} else if mediumMeteor[i].position.y < 0 - mediumMeteor[i].radius {mediumMeteor[i].position.y = screenHeight + mediumMeteor[i].radius}
	}
	for i in 0 ..< MAX_SMALL_METEORS {

		if !smallMeteor[i].active do continue
		// Movement
		smallMeteor[i].position += smallMeteor[i].speed

		// Collision logic: meteor vs. wall
		if smallMeteor[
			   i \
		   ].position.x >
		   screenWidth +
			   smallMeteor[
					   i \
				   ].radius {smallMeteor[i].position.x = -smallMeteor[i].radius} else if smallMeteor[i].position.x < 0 - smallMeteor[i].radius {smallMeteor[i].position.x = screenWidth + smallMeteor[i].radius}
		if smallMeteor[
			   i \
		   ].position.y >
		   screenHeight +
			   smallMeteor[
					   i \
				   ].radius {smallMeteor[i].position.y = -smallMeteor[i].radius} else if smallMeteor[i].position.y < 0 - smallMeteor[i].radius {smallMeteor[i].position.y = screenHeight + smallMeteor[i].radius}
	}

	// Collision logic: player-shoots vs. meteors
	for i in 0 ..< PLAYER_MAX_SHOOTS {
		if !shoot[i].active do continue
		for a := 0; a < MAX_BIG_METEORS; a += 1 {
			if bigMeteor[
				   a \
			   ].active &&
			   rl.CheckCollisionCircles(
				   shoot[i].position,
				   shoot[i].radius,
				   bigMeteor[a].position,
				   bigMeteor[a].radius,
			   ) {
				shoot[i].active = false
				shoot[i].lifeSpawn = 0
				bigMeteor[a].active = false
				destroyedMeteorsCount += 1

				for j in 0 ..< 2 {
					if midMeteorsCount % 2 == 0 {
						mediumMeteor[midMeteorsCount].position = bigMeteor[a].position
						mediumMeteor[midMeteorsCount].speed = {
							cos(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED * -1,
							sin(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED * -1,
						}
					} else {
						mediumMeteor[midMeteorsCount].position = bigMeteor[a].position
						mediumMeteor[midMeteorsCount].speed = {
							cos(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED,
							sin(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED,
						}
					}
					mediumMeteor[midMeteorsCount].active = true
					midMeteorsCount += 1
				}
				//bigMeteor[a].position = {-100, -100}
				bigMeteor[a].color = rl.RED
				breaksound()
				a = MAX_BIG_METEORS
			}
		}
		for b := 0; b < MAX_MEDIUM_METEORS; b += 1 {
			if !mediumMeteor[b].active do continue
			if rl.CheckCollisionCircles(
				shoot[i].position,
				shoot[i].radius,
				mediumMeteor[b].position,
				mediumMeteor[b].radius,
			) {
				shoot[i].active = false
				shoot[i].lifeSpawn = 0
				mediumMeteor[b].active = false
				destroyedMeteorsCount += 1

				for j in 0 ..< 2 {
					if smallMeteorsCount % 2 == 0 {
						smallMeteor[smallMeteorsCount].position = mediumMeteor[b].position
						smallMeteor[smallMeteorsCount].speed = {
							cos(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED * -1,
							sin(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED * -1,
						}
					} else {
						smallMeteor[smallMeteorsCount].position = mediumMeteor[b].position
						smallMeteor[smallMeteorsCount].speed = {
							cos(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED,
							sin(shoot[i].rotation * rl.DEG2RAD) * METEORS_SPEED,
						}
					}
					smallMeteor[smallMeteorsCount].active = true
					smallMeteorsCount += 1
				}
				//bigMeteor[b].position = {-100, -100}
				mediumMeteor[b].color = rl.GREEN
				breaksound()
				b = MAX_MEDIUM_METEORS
			}
		}
		for c := 0; c < MAX_SMALL_METEORS; c += 1 {
			if !smallMeteor[c].active do continue
			if rl.CheckCollisionCircles(
				shoot[i].position,
				shoot[i].radius,
				smallMeteor[c].position,
				smallMeteor[c].radius,
			) {
				shoot[i].active = false
				shoot[i].lifeSpawn = 0
				smallMeteor[c].active = false
				destroyedMeteorsCount += 1
				//smallMeteor[a].position = {-100, -100}
				smallMeteor[c].color = rl.YELLOW
				breaksound()
				c = MAX_SMALL_METEORS
			}
		}
	}

	if destroyedMeteorsCount == MAX_BIG_METEORS + MAX_MEDIUM_METEORS + MAX_SMALL_METEORS {
		victory = true
	}
}

DrawGame :: proc() {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.RAYWHITE)

	if gameOver {
		msg :: "PRESS [ENTER] TO PLAY AGAIN"
		rl.DrawText(
			msg,
			rl.GetScreenWidth() / 2 - rl.MeasureText(msg, 20) / 2,
			rl.GetScreenHeight() / 2 - 50,
			20,
			rl.GRAY,
		)
		when #config(audio, true) do sv_volume(0, 256 / 7)
		return
	}

	// Draw spaceship
	v1: rl.Vector2 = {
		player.position.x + sin(player.rotation * rl.DEG2RAD) * shipHeight,
		player.position.y - cos(player.rotation * rl.DEG2RAD) * shipHeight,
	}
	v2: rl.Vector2 = {
		player.position.x - cos(player.rotation * rl.DEG2RAD) * PLAYER_BASE_SIZE / 2,
		player.position.y - sin(player.rotation * rl.DEG2RAD) * PLAYER_BASE_SIZE / 2,
	}
	v3: rl.Vector2 = {
		player.position.x + cos(player.rotation * rl.DEG2RAD) * PLAYER_BASE_SIZE / 2,
		player.position.y + sin(player.rotation * rl.DEG2RAD) * PLAYER_BASE_SIZE / 2,
	}
	rl.DrawTriangle(v1, v2, v3, rl.MAROON)

	// Draw meteors
	for i in 0 ..< MAX_BIG_METEORS {
		if bigMeteor[i].active {
			rl.DrawCircleV(bigMeteor[i].position, bigMeteor[i].radius, rl.DARKGRAY)
		} else {
			rl.DrawCircleV(bigMeteor[i].position, bigMeteor[i].radius, rl.Fade(rl.LIGHTGRAY, 0.3))
		}
	}
	for i in 0 ..< MAX_MEDIUM_METEORS {
		if mediumMeteor[i].active {
			rl.DrawCircleV(mediumMeteor[i].position, mediumMeteor[i].radius, rl.DARKGRAY)
		} else {
			rl.DrawCircleV(
				mediumMeteor[i].position,
				mediumMeteor[i].radius,
				rl.Fade(rl.LIGHTGRAY, 0.3),
			)
		}
	}
	for i in 0 ..< MAX_SMALL_METEORS {
		if smallMeteor[i].active {
			rl.DrawCircleV(smallMeteor[i].position, smallMeteor[i].radius, rl.GRAY)
		} else {
			rl.DrawCircleV(
				smallMeteor[i].position,
				smallMeteor[i].radius,
				rl.Fade(rl.LIGHTGRAY, 0.3),
			)
		}
	}

	// Draw shoot
	for i in 0 ..< PLAYER_MAX_SHOOTS {
		if shoot[i].active do rl.DrawCircleV(shoot[i].position, shoot[i].radius, rl.BLACK)
	}

	if victory do rl.DrawText("VICTORY", screenWidth / 2 - rl.MeasureText("VICTORY", 20) / 2, screenHeight / 2, 20, rl.LIGHTGRAY)
	if pause do rl.DrawText("GAME PAUSED", screenWidth / 2 - rl.MeasureText("GAME PAUSED", 40) / 2, screenHeight / 2 - 40, 40, rl.GRAY)
}

// Unlada game variables
UnloadGame :: proc() {
	// TODO: Unload all dynamic loaded data (textures, sounds, models...)
}

UpdateDrawFrame :: proc() {
	UpdateGame()
	DrawGame()
}

