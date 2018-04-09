# mpv-scripts
These are scripts written for mpv.   

## show_filename.lua
A simple script to show the name of current playing file.  To use this function, you need to press `SHIFT+ENTER`. 

Besides, for better experience, you could adjust the `osd-font-size` property in mpv.conf  

For example:
```
osd-font-size=30
```

## bookmark.lua
This is originally coded by my friend [sorayuki](!https://github.com/sorayuki-winter/mpv-plugin-bookmark). Since I believe using mpv.conf is more convenient and safer. I removed the function which will save positions all the time during playing time. 

In order to start resume from the exit point, you just need to add a line in the mpv.conf
```
save-position-on-quit
```