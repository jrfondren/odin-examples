package main

import "core:fmt"
import "core:math"
sin, cos :: math.sin, math.cos
import rl "vendor:raylib"

//------------------------------------------------------------------------------------
// Program main entry point
//------------------------------------------------------------------------------------
main :: proc() {
	// Initialization
	//--------------------------------------------------------------------------------------
	screenWidth, screenHeight :: 800, 450

	rl.InitWindow(screenWidth, screenHeight, "raylib [models] example - first person maze")

	// Define the camera to look into our 3d world
	camera := rl.Camera{{ 0.2, 0.4, 0.2 }, {0, 0, 0}, {0, 1, 0 }, 45, {} }
	imMap := rl.LoadImage("resources/cubicmap.png")
	if imMap.data == nil {
		fmt.eprintln("failed to load resources/cubicmap.png")
		return
	}
	cubicmap := rl.LoadTextureFromImage(imMap)
	mesh := rl.GenMeshCubicmap(imMap, {1, 1, 1})
	model := rl.LoadModelFromMesh(mesh)

	// NOTE: By default each cube is mapped to one part of texture atlas
	texture := rl.LoadTexture("resources/cubicmap_atlas.png")
	if texture == {} {
		fmt.eprintln("failed to load resources/cubicmap_atlas.png")
		return
	}
	model.materials[0].maps[rl.MaterialMapIndex.DIFFUSE].texture = texture             // Set map diffuse texture

	// Get map image data to be used for collision detection
	mapPixels := rl.LoadImageColors(imMap)
	rl.UnloadImage(imMap)             // Unload image from RAM

	mapPosition := rl.Vector3{ -16, 0, -8 }  // Set model position

	rl.SetCameraMode(camera, rl.CameraMode.FIRST_PERSON)     // Set camera mode

	rl.SetTargetFPS(60)               // Set our game to run at 60 frames-per-second
	//--------------------------------------------------------------------------------------

	// Main game loop
	for !rl.WindowShouldClose() {   // Detect window close button or ESC key
		// Update
		//----------------------------------------------------------------------------------
		oldCamPos := camera.position    // Store old camera position

		rl.UpdateCamera(&camera)

		// Check player collision (we simplify to 2D collision detection)
		playerPos := rl.Vector2{ camera.position.x, camera.position.z }
		playerRadius : f32 = 0.1  // Collision radius (player is modelled as a cilinder for collision)

		playerCellX := i32(playerPos.x - mapPosition.x + 0.5)
		playerCellY := i32(playerPos.y - mapPosition.z + 0.5)

		// Out-of-limits security check
		if playerCellX < 0 { playerCellX = 0 }
		else if playerCellX >= cubicmap.width { playerCellX = cubicmap.width - 1 }

		if playerCellY < 0 { playerCellY = 0 }
		else if playerCellY >= cubicmap.height { playerCellY = cubicmap.height - 1 }

		// Check map collisions using image data and player position
		// TODO: Improvement: Just check player surrounding cells for collision
		for y in 0 ..< cubicmap.height {
			for x in 0 ..< cubicmap.width {
			       // Collision: white pixel, only check R channel
				if mapPixels[y*cubicmap.width +x].r == 255 && rl.CheckCollisionCircleRec(playerPos, playerRadius, {mapPosition.x - 0.5 + f32(x), mapPosition.z - 0.5 + f32(y), 1, 1}) {
					// Collision detected, reset camera position
					camera.position = oldCamPos
				}
			}
		}
		//----------------------------------------------------------------------------------

		// Draw
		//----------------------------------------------------------------------------------
		rl.BeginDrawing()

		rl.ClearBackground(rl.RAYWHITE)

		rl.BeginMode3D(camera)
		rl.DrawModel(model, mapPosition, 1, rl.WHITE);                     // Draw maze map
		rl.EndMode3D()

		rl.DrawTextureEx(cubicmap, { f32(rl.GetScreenWidth() - cubicmap.width*4 - 20), 20 }, 0, 4, rl.WHITE)
		rl.DrawRectangleLines(rl.GetScreenWidth() - cubicmap.width*4 - 20, 20, cubicmap.width*4, cubicmap.height*4, rl.GREEN)

		// Draw player position radar
		rl.DrawRectangle(rl.GetScreenWidth() - cubicmap.width*4 - 20 + playerCellX*4, 20 + playerCellY*4, 4, 4, rl.RED);

		rl.DrawFPS(10, 10)

		rl.EndDrawing()
		//----------------------------------------------------------------------------------
	}

	// De-Initialization
	//--------------------------------------------------------------------------------------
	rl.UnloadImageColors(mapPixels)   // Unload color array

	rl.UnloadTexture(cubicmap)        // Unload cubicmap texture
	rl.UnloadTexture(texture)         // Unload map texture
	rl.UnloadModel(model)             // Unload map model

	rl.CloseWindow()                  // Close window and OpenGL context
	//--------------------------------------------------------------------------------------
}
