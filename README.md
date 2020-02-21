# mpv-scripts
These are scripts written for mpv.

## How to use
For Linux, move the `*.lua` files into `~/.config/mpv/scripts/`

## show_filename.lua
A simple script to show the name of current playing file.  To use this function, you need to press `SHIFT+ENTER`.

Besides, for better experience, you could adjust the `osd-font-size` property in mpv.conf  

For example:
``` txt
osd-font-size=30
```

## bookmark.lua
This script helps you to create a history file in the video folder. The next time you want to continue to watch it, you can open any videos in the folder. The script will lead you to the video played last time.

It is originally coded by my friend [sorayuki](https://github.com/sorayuki-winter/mpv-plugin-bookmark). Since I believe using mpv.conf is more convenient and safer. I removed the function which will save positions all the time during playing time.

In order to start resume from the exit point, you just need to add a line in the mpv.conf

``` txt
save-position-on-quit
```
