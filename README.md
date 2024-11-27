# samba - (ghcr.io/fawzibr/samba) [x86 + arm]

samba on alpine

with timemachine, zeroconf (`avahi`), WSD (Web Services for Devices) (`wsdd2`) and added dynamic share support.

This fork is based on https://github.com/ServerContainers/samba, look for main documentation there.

## Build & Variants

You can specify `DOCKER_REGISTRY` environment variable (for example `my.registry.tld`)
and use the build script to build the main container and it's variants for _x86_64, arm64 and arm_

You'll find all images tagged like `a3.15.0-s4.15.2` which means `a<alpine version>-s<samba version>`.
This way you can pin your installation/configuration to a certain version. or easily roll back if you experience any problems.

To build a `latest` tag run `./build.sh release`

For builds without specified registry you can use the `generate-variants.sh` script to generate 
variations of this container and build the repos yourself.

_all of those variants are automatically build and generated in one go_

- `latest` or `a<alpine version>-s<samba version>`
    - main version of this repo
    - includes everything (smbd, avahi, wsdd2)
    - not all services need to start/run -> use ENV variables to disable optional services
- `smbd-only-latest` or `smbd-only-a<alpine version>-s<samba version>`
    - this will only include smbd and my scripts - no avahi, wsdd2 installed
- `smbd-avahi-latest` or `smbd-avahi-a<alpine version>-s<samba version>`
    - this will only include smbd, my scripts and avahi
    - optional service can still be disabled using ENV variables
- `smbd-wsdd2-latest` or `smbd-wsdd2-a<alpine version>-s<samba version>`
    - this will only include smbd, my scripts and wsdd2
    - optional service can still be disabled using ENV variables

## Dynamic Volumes

You can add a host directory to the samba container and add shares to it. The volume name is '/dynamic-volumes'.
After that you can do the following:

* Add directory - just create a directory and it will be automatically added as a share. It will only 
add path, comment and writeable. If you want extra key/values to the share (like 'guest ok') just create 
a file names '<sharename>.template' with the keys, if not found it will use 'default.template'.

* Add a share file - create a file named '<sharename>.share' with the samba share information.

* Refresh shares - to refresh shares with webhook just make a request to http://yourserver:9000/hooks/refresh-config
If environment variable _SAMBA\_DYNAMIC\_VOLUMES_ is set it will check the folder every minute.

## Changelogs

* 2024-11-26
    * changed a lot of stuff internally, added webhook to refresh config
* 2024-10-28
    * changed variable name so it's not mistaken as creating user shares, just a regular share
* 2024-10-27
    * skipped using usershares, now just creating normal shares and reloading the config file
* 2024-10-16
    * made public

## Environment variable added 

### Samba

*  _SAMBA\_DYNAMIC\_VOLUMES_
    * _optional_
    * value: yes|true|y (default not set)
    * flag to enable periodic check for user shares 
    * files must be named 'sharename.share', contents are the values of a normal samba share. See the samba documentation
