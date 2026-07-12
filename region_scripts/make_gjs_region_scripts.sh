#!/bin/bash

template="gjs-region-template.lua"
outdir="region_scripts"

mkdir -p "$outdir"

for n in $(seq 1 16); do
  sed "s/__REGION__/${n}/g" "$template" > "$outdir/gjs-Region_${n}.lua"
done

echo "Klaar. Scripts aangemaakt in: $outdir/"#!/bin/bash

