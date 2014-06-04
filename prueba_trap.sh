#!/bin/bash

function pepe()
{
   echo 5
}

trap "pepe" 2

while true
do
   sleep 1
done

