#!/bin/bash

# Check for the correct number of arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 {on|off}"
    exit 1
fi

# Process the input argument to decide which command to run
if [ "$1" == "on" ]; then
    echo 0 | tee /sys/class/backlight/*/bl_power
    echo "Screen turned ON."
elif [ "$1" == "off" ]; then
    echo 1 | tee /sys/class/backlight/*/bl_power
    echo "Screen turned OFF."
else
    echo "Invalid argument. Usage: $0 {on|off}"
    exit 1
fi