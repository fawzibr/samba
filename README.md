# samba - (ghcr.io/fawzibr/samba) [x86 + arm]

samba on alpine

with timemachine, zeroconf (`avahi`), WSD (Web Services for Devices) (`wsdd2`) and added usershare support.

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

## Changelogs

* 2024-10-27
    * skipped using usershares, now just creating normal shares and reloading the config file
* 2024-10-16
    * made public

## Environment variable added 

### Samba

*  __SAMBA\_USERSHARES\_DIR__
    * _optional_
    * default not set
    * location for all usershare files 
    * files must be named 'sharename.share', contents are the values of a normal samba share. See the samba documentation
