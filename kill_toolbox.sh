#!/bin/bash

# kill掉服务器的toolbox的进程，解决jetbrains的pycharm卡死连不上问题

kill -9 $(pgrep -u $USER -f pycharm)
kill -9 $(pgrep -u $USER -f toolbox)
