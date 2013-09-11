#!/bin/sh

ruby hex.rb firmware_2.cpp.hex  | awk '{print "      \"" $1 "\\n\""}'
