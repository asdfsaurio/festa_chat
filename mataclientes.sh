#!/bin/bash

cat log_client_*.txt | gawk -F'|' '{print $2}' | xargs kill
rm log_client_*.txt

