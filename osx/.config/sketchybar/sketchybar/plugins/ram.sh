#!/usr/bin/env bash

# Get total physical memory in bytes
total_mem_bytes=$(sysctl -n hw.memsize)

# Get page size in bytes
page_size=$(sysctl -n vm.pagesize)

# Get relevant page counts using one awk command
read free_pages inactive_pages speculative_pages <<< $(vm_stat | awk \
    '/Pages free/ {free=$3} \
     /Pages inactive/ {inactive=$3} \
     /Pages speculative/ {speculative=$3} \
     END {print free, inactive, speculative}' | tr -d '.')

# Sum pages considered potentially "available" (Free + Inactive + Speculative)
non_active_pages=$((free_pages + inactive_pages + speculative_pages))

# Calculate non-active memory in bytes
non_active_mem_bytes=$((non_active_pages * page_size))

# Calculate used memory in bytes (Total - NonActive)
used_mem_bytes=$((total_mem_bytes - non_active_mem_bytes))

# Calculate used memory percentage
# Ensure we don't divide by zero or get negative results (edge cases)
if [ $total_mem_bytes -gt 0 ]; then
  used_mem_percentage=$((used_mem_bytes * 100 / total_mem_bytes))
  if [ $used_mem_percentage -lt 0 ]; then
    used_mem_percentage=0
  elif [ $used_mem_percentage -gt 100 ]; then
    used_mem_percentage=100 # Cap at 100 in case of calculation nuances
  fi
else
  used_mem_percentage=0
fi

sketchybar --set $NAME label="${used_mem_percentage}%"