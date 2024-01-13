# mpv-scripts

[![Static Badge](https://img.shields.io/badge/README-%E4%B8%AD%E6%96%87-blue)](./README.zh-CN.md)

These are scripts written for mpv.

## How to use

- Windows: move `*.lua` files into `<path of mpv>/scripts/`
- Linux: move `*.lua` files into `~/.config/mpv/scripts/`

## show_filename.lua

A simple script to show the name of current playing file.  To use this function, you need to press `SHIFT+ENTER`. For better experience, you could adjust the `osd-font-size` property in mpv.conf

For example:

``` txt
osd-font-size=30
```

## history-bookmark.lua

This script will create a history folder in `.config/mpv/history/` (unix like system) or `%APPDATA%\mpv\history\` (windows). The history folder contains records of the videos you have watched. The next time you want to continue to watch it, you can open any videos in the folder. The script will lead you to the video played last time.

![history-bookmark](./res/history-bookmark.png)

As shown in the screenshot, last time we watched episode 1. Now we can press `ENTER` to jump to ep1, press `n` or do nothing to stay in the episode we are watching now.

In order to resume from the exact point of the watching progress in target episode, you just need to add a line in the mpv.conf

``` txt
save-position-on-quit
```

## Other scripts I recommend

[autoload](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua): Automatically load playlist entries before and after the currently playing file, by scanning the directory.

## Contributors

<a href="https://github.com/yuukidach/mpv-scripts/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=yuukidach/mpv-scripts" />
</a>
