# Asteroids

A mostly direct Odin port of a mostly direct D port of a C raylib example.

This version has some BGM and sound effects.

# Play without audio
```
$ odin run . -define:audio=false
```

# Play with sunvox audio
1. get SunVox library for developers from https://www.warmplace.ru/soft/sunvox/ (get SunVox as well to alter the provided audio.)
2. place the appropriate sunvox.so (changing the name in the source if necessary) in the current directory
3. build, on linux, with `make`

# SunVox notice
Powered by SunVox (modular synth & tracker)
Copyright (c) 2008 - 2022, Alexander Zolotov <nightradio@gmail.com>, WarmPlace.ru
