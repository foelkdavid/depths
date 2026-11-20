# DEPTHS

A mech expedition below the ash: a voxel, path-traced twin-stick roguelike built on
[vpt-engine](engine/) (included as a git submodule).

## Setup

```sh
git clone --recurse-submodules <depths>     # or, in an existing clone:
git submodule update --init
```

Needs `c3c` 0.8.x; raylib comes with the engine.

## Build

```sh
c3c build depths         # the game        -> build/depths
c3c build depths-dev     # editor + game   -> build/depths-dev (P on a mech plays, New World generates layers)
```

Release (one file with all assets packed in): `python3 engine/tools/make-release.py depths` → `dist/depths`.

## Layout

| Folder | |
|---|---|
| `src/` | the game: mechs, creatures, layers, skills, bestiary |
| `app/` | the game app: main menu, settings |
| `assets/` | models, sounds, sky, icons |
| `engine/` | vpt-engine (submodule) |
| `archive/` | old assets and scenes, browsable in `depths-dev` |
| `dev/` | test suites, asset generators, tools and notes |
