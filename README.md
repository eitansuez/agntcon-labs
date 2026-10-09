# runlab-labs

Lessons for the runlab platform. One directory is one lab, and the directory name is the lab name.

A lab has `index.md`, the lesson the page renders. `config.yaml` is optional. `setup.sh` is optional. The disk build runs it once, as root, after copying `data/` to `/root/data`. The script can install a service that runs on later boots.

The platform stores the disk. Changing `setup.sh`, `data/`, or `disk_gib` builds a new one. The lesson, the title, the description, `memory_mib`, `vcpus`, `time_limit`, `env`, `services`, and `snapshot` do not.

## config.yaml

Every field can be omitted.

`title` and `description` are the text on the catalog page. `author` is who wrote the lab.

`memory_mib` is the guest RAM. The default is 1024. `vcpus` defaults to 2.

`time_limit` is how long a session may run, written as `10m` or `600s`. The default is 10 minutes. The microVM is reclaimed when the limit hits, and when the learner completes the lab.

`disk_gib` is the size of the built disk. The default is 8. Launch does not read it.

`snapshot: true` asks the labs boot job to save a memory snapshot once the disk is current. Launch does not read it. A later launch resumes that snapshot when it still matches the disk.

`env` is copied into the guest after SSH is up. The name on the left is the guest variable. A value that starts with `$` is taken from the catalog environment, and the launch stops if that variable is empty. The template disk does not contain it.

`services` are links on the lesson page. Each entry has a `name`, a guest `port`, and a `path` that starts with `/`. An omitted path is `/`.

```yaml
memory_mib: 2048
vcpus: 2
disk_gib: 16
time_limit: 15m
snapshot: true
title: Example
description: What the catalog shows.
env:
  LAB_TRACK: $LAB_TRACK
services:
  - name: App
    port: 4000
    path: /ui
```
