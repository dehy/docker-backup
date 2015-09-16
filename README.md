# akerbis/data-container-backup

Docker image for backuping data containers, using [duplicity](http://duplicity.nongnu.org/index.html) as its core.

## Howto

### Define environment variables

- BACKUP_METHOD = ftp | s3 (s3 not working for now)
- BACKUP_URL = server_url (ie. ftp://backupuser@ftpbackup.company.com)

If _ftp_ backup method :
- FTP_PASSWORD = some_password

If _s3_ backup method:
- BACKUP_S3_ACCESS_KEY_ID = your aws access key id
- BACKUP_S3_SECRET_ACCESS_KEY = your aws secret access key

### Define containers volumes to backup

As docker command, with the syntax container_name:/exported/volume separated by white-space in case of multi backups

## Example

    # docker run  -v /var/run/docker.sock:/var/run/docker.sock \
        -e "BACKUP_URL=ftp://backupuser@backup.mycompany.com" \
        -e "FTP_PASSWORD=backuppassword" \
        -e "BACKUP_METHOD=ftp" \
        akerbis/data-container-backup \
        container_name:/exported/volume

## TODO

- Make volume optional. In this case, backup all volumes from the container.
- Test input data in the script.
- Make S3 backup work, that'd be great.
- Export the Dockerfile commands in a build.sh script.
- Create a docker-compose.yml file and add Tutum Deploy button
