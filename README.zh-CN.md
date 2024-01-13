# mpv-scripts

[![Static Badge](https://img.shields.io/badge/README-English-blue)](./README.md)

这些是为 mpv 编写的脚本。

## 使用方法

- Windows：将 `*.lua` 文件移动到 `<mpv安装目录>/scripts/`
- Linux：将 `*.lua` 文件移动到 `~/.config/mpv/scripts/`

## show_filename.lua

显示当前播放文件名的简单脚本。要使用此功能，您需要按 `SHIFT+ENTER`。为了更好的体验，您可以调整 mpv.conf 中的 `osd-font-size` 属性，例如：

``` txt
osd-font-size=30
```

## history-bookmark.lua

此脚本将在 `.config/mpv/history/`（类Unix系统）或 `%APPDATA%\mpv\history\`（Windows）中创建一个历史文件夹。历史文件夹包含您观看的视频的记录。下次您想继续观看它时，您可以在文件夹中打开任何视频。脚本将引导您到上次播放的视频。

![history-bookmark](./res/history-bookmark.png)

如屏幕截图所示，上次我们观看了第1集。现在我们可以按 `ENTER` 跳转到第1集，按 `n` 或什么都不做以停留在我们现在正在观看的集数。

为了从目标集数的观看进度的确切点继续观看，您只需要在 mpv.conf 中添加一行：

``` txt
save-position-on-quit
```

## 其他我推荐的脚本

[autoload](https//github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua)：通过扫描目录，在当前播放文件之前和之后自动加载播放列表条目。
