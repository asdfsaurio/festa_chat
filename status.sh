#!/bin/bash

ARGS=$(cat pids.txt | gawk -F'|' '{printf "-e %d ", $2}')

ps -eaf | grep $ARGS | grep -v grep

