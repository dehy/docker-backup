# akerbis/docker-backup

[![](https://images.microbadger.com/badges/image/akerbis/docker-backup.svg)](https://microbadger.com/images/akerbis/docker-backup "Get your own image badge on microbadger.com") [![](https://images.microbadger.com/badges/version/akerbis/docker-backup.svg)](https://microbadger.com/images/akerbis/docker-backup "Get your own version badge on microbadger.com") [![](https://images.microbadger.com/badges/commit/akerbis/docker-backup.svg)](https://microbadger.com/images/akerbis/docker-backup "Get your own commit badge on microbadger.com")

Docker image for orchestrating backup of data and mysql containers, using [duplicity](http://duplicity.nongnu.org/index.html) at its core.

## Warning

This app is currently very very early-stage. Consider using it at your own risks and do not use it on production systems.

## Howto

### Configuration

You need to copy `app/config.yml.dist` to `app/config.yml` and override parameters.

You can defines destinations (backup servers), sources (datas to backup) and some global parameters. Supported destinations are `ftp`, `sftp` and `s3`. Supported sources are `fs` and `mysqldump`.

sources can also be specified directly using environment variables of it container.
       environment:
          - DB_DESTINATION=local-ftp
          - DB_DESTPATH=container-name
          - DB_VOLUMES=/data
          - DB_PRECMD="mysqldump all > /data/dump.sql"
          - DB_POSTCMD="echo done"

DB_PRECMD, DB_POSTCMD support left to be added.


#### Required parameters for destinations

For all destination, define a parameter `type` with a value of `ftp`, `sftp` or `s3` with the following parameters:

##### ftp / sftp
- server
- port
- username
- password
- path

##### s3
- region
- bucket_name
- access_key_id
- secret_access_key

#### Required parameters for sources

For all sources, define a parameter `destination` and a parameter `type` with a value of `fs` or `mysqldump` with the following parameters:

##### fs
- container
- volumes (as array)

##### mysqldump
- container
- username
- password
- databases (as array)

### Sample configuration

Read the `app/config.yml.dist` file

## Use

You need to pass the docker socket and your custom configuration file as volumes.
By default, the container launch a cron process with a daily trigger of the script.

    docker run -d \
        -v /host/path/to/config.yml:/etc/docker-backup/docker-backup.yml \
        -v /var/run/docker.sock:/var/run/docker.sock \
        akerbis/docker-backup

You can force a backup with the `force` command:

    docker run \
        -v /host/path/to/config.yml:/etc/docker-backup/docker-backup.yml \
        -v /var/run/docker.sock:/var/run/docker.sock \
        akerbis/docker-backup force

### Override config parameters with env variables

You may need to provide parameters such as credentials as external values from
the configuration. You can provides such information through environment variables
formatted with this rule :
  - Start with `CONFIG_`
  - Concatenate the path from configuration with underscores `_`
  - Make it uppercase
  - Replace any non-alpha and underscore character with underscore.

ie. if I want to provides the secret access key of the destination "s3" from the
`app/config.yml.dist` provided, I simply follow the path `destinations` > `s3` > `secret_access_key`.
The environment variable is then called `CONFIG_DESTINATIONS_S3_SECRET_ACCESS_KEY`.

## Restore

Restoring a backup is easy: use the `restore [container ...]` command. This will
restore the last backup to the `/docker-restore` mounted path.

    docker run \
        -v /host/path/to/config.yml:/etc/docker-backup/docker-backup.yml \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /host/path/to/restored/content:/docker-restore:rw \
        akerbis/docker-backup restore test_fs

For mysql backups, the restore action will simply restore the dumped .sql file.

## How it works

This image uses the docker socket to connect and backup files, depending on the source type of the container to backup. For each source to backup, it will spawn a *worker* container whom task is to handle the backup itself. The main container keep the backup orchestration.
For example, a `fs` source type will backuped by mounting the source container volumes to the worker backup container and execute the backup from here. The worker backup container is then stopped and removed.
A `mysqldump` source type will be backuped by executing (`docker exec`) the `mysqldump` command into the source container, redirecting the output to the worker backup container, and execute the backup from here.

The backup execution itself is handled by [`duplicity`](http://duplicity.nongnu.org)

## Authors

- Arnaud de Mouhy <arnaud.demouhy@akerbis.com>

## Contributions

Feel free to fork the project and propose Pull Requests!

## TODO

See [Issues](https://github.com/akerbis/docker-backup/issues).
