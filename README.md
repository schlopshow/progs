# Schlop's Program Files for Automatic Installation of Arch Based Distros

## full-prgs.csv
  Contains all of the different applications, my reccomedation is to not use this file without commenting out parts you don't need.

## laptop.csv
  Contains applications for my laptop setup.

## nvidia-desktop.csv
  Contains applications and drivers for my desktop. I am using the latest nvidia drivers with all the reccomended packages,
  but it might not work outside of the box. I recommend looking at the [arch wiki](https://wiki.archlinux.org/title/NVIDIA) nvidia page if you come into issues.
  
## pentest.csv
  Contains pentesting and capture the flag tools and  applications for my virtual machine.

## server.csv
  Contains all the neccessary applications and package for my servers.

# How to Use

  Combine progs.csv file with Luke Smith's larbs.sh script with the -p option.

  ```
  larbs.sh -p progs.csv
  ```
  Replace progs.csv with any of the csv files in the github for a different  automatic installation.
