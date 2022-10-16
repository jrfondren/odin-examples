package main

import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(800, 800, "Hello, Raylib!")
	defer rl.CloseWindow()

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.EndDrawing()
		rl.ClearBackground(rl.BLACK)
		rl.DrawText("Hello, world!", 400, 300, 28, rl.RAYWHITE)
		rl.DrawText("Hello, world!", 400, 400, 28, rl.RED)
	}
}
