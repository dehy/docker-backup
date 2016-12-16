# akerbis/docker-backup

Docker image for backuping data and mysql containers, using [duplicity](http://duplicity.nongnu.org/index.html) at its core.

## Warning

This app is currently very very early-stage. Consider using it at your own risks and do not use it on production systems.

## Howto

### Configuration

You need to copy `app/config.yml.dist` to `app/config.yml` and override parameters.

You can defines destinations (backup servers), sources (datas to backup) and some global parameters. Supported destinations are `ftp` and `s3`. Supported sources are `fs` and `mysqldump`.

#### Required parameters for destinations

For all destination, define a parameter `type` with a value of `ftp` or `s3` with the following parameters:

##### ftp
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

## How it works

This image uses the docker socket to connect and backup files, depending on the source type of the container to backup. For each source to backup, it will run by itself a *worker* container whom task is to handle the backup itself. The main container keep the backup orchestration.
For example, a `fs` source type will backuped by mounting the source container volumes to the worker backup container and execute the backup from here. The worker backup container is then stopped and removed.
A `mysqldump` source type will be backuped by executing (`docker exec`) the `mysqldump` command into the source container, redirecting the output to the worker backup container, and execute the backup from here.

The backup execution itself is handled by [`duplicity`](http://duplicity.nongnu.org)

## Authors

- Arnaud de Mouhy <arnaud.demouhy@akerbis.com>

## Contributions

Feel free to fork the project and propose Pull Requests!

## TODO

- Check all parameters validity before starting
- Check and tighten security
- Make a restore action
- [Multi Backend](http://duplicity.nongnu.org/duplicity.1.html#sect18)
- Encryption
- Web Interface
- Docker-Cloud API integration
