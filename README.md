# Pocket VN

A touch-first visual-novel starter project for Godot 4 and Android. The project is GDScript source; no APK has been exported.

## Other projects and downloads

This repository also contains the separate Aoi projects:

- **Aoi Mobile** — full Godot source in [Aoi_Mobile_3.2.14-dev_stabilization-pass-05](Aoi_Mobile_3.2.14-dev_stabilization-pass-05/). Open its `project.godot` with Godot 4.8 beta 1.
- **Aio GPT6 Mini** — the experimental Python project in [gpt6mini](gpt6mini/). Its [README](gpt6mini/README.md) includes run and test instructions.
- **Pocket VN** — this repository's root Godot project, including its [story](stories/demo.json), [art](art/), and [engine script](scripts/vn_engine.gd).

Downloadable files:

- [Aoi Mobile Android APK](https://github.com/jayzyee/aio/releases/download/aoi-mobile-3.2.14-dev/aoi-mobile-3.2.14-dev.apk)
- [Aoi Mobile source ZIP](https://github.com/jayzyee/aio/releases/download/aoi-mobile-3.2.14-dev/Aoi-Mobile-3.2.14-dev-source.zip)
- [Aio GPT6 Mini source ZIP](https://github.com/jayzyee/aio/releases/download/aoi-mobile-3.2.14-dev/Aio-GPT6-Mini-source.zip)
- [Pocket VN source ZIP](https://github.com/jayzyee/aio/releases/download/aoi-mobile-3.2.14-dev/Pocket-VN-source.zip)
- [All source projects ZIP](https://github.com/jayzyee/aio/archive/refs/heads/main.zip)

## Run it

1. Open this folder in Godot 4.
2. Run `Main.tscn` (or press F6 after opening it).
3. Use the on-screen choices to play the sample story. Save and Load use Godot's `user://savegame.json`.

The project starts in portrait orientation and uses Godot's Compatibility renderer for broad mobile support. Android packaging and signing can be configured later in Godot's export settings.

## Capture an offscreen preview

On Linux, Godot can render the running project to PNG frames without a physical display by using Xvfb and software OpenGL:

```sh
xvfb-run -a -s '-screen 0 720x1280x24' env LIBGL_ALWAYS_SOFTWARE=1 godot --path . --write-movie /tmp/vn.png --quit-after 1 --fixed-fps 1
```

Godot writes a numbered frame such as `/tmp/vn00000000.png`. A sample capture is available at [screenshots/demo.png](screenshots/demo.png).

## Write a story

Edit `stories/demo.json`. Each story has a `start` node id and a `nodes` array. Nodes need unique `id` and `text` fields. `character`, `background`, and `portrait` are optional. A node either has a `next` id for linear dialogue or a `choices` array for branching:

```json
{
  "id": "crossroads",
  "character": "Mira",
  "text": "Which road should we take?",
  "background": "res://art/blue_hour.svg",
  "portrait": "res://art/mira.svg",
  "choices": [
    { "text": "Follow the river.", "next": "river" },
    { "text": "Climb the hill.", "next": "hill" }
  ]
}
```

Every choice target and every non-empty `next` target must refer to an existing node. A node with no choices and no `next` is an ending. Image fields should use Godot resource paths, such as `res://art/mira.svg`.

The player and story validation live in `scripts/vn_engine.gd`. The UI is built in code to keep this starter easy to customize without scene-editor setup.
