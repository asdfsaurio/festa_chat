#!/bin/bash

cat LOG.txt | gawk -F'|' '{print $2}' | xargs kill

