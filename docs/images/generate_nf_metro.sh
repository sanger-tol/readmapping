#!/bin/sh

## render static maps
nf-metro render readmapping.mmd \
    -o sanger-tol-readmapping_metro_map_dark.svg \
    --logo sanger-tol-readmapping_logo_dark.png
nf-metro render readmapping.mmd \
    -o sanger-tol-readmapping_metro_map_light.svg \
    --theme light \
    --logo sanger-tol-readmapping_logo_light.png

## render animated maps
nf-metro render readmapping.mmd \
    --animate \
    -o sanger-tol-readmapping_metro_map_dark_animated.svg \
    --logo sanger-tol-readmapping_logo_dark.png
nf-metro render readmapping.mmd \
    --animate \
    -o sanger-tol-readmapping_metro_map_light_animated.svg \
    --theme light \
    --logo sanger-tol-readmapping_logo_light.png
