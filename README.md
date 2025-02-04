# Unimus Backup Exporter 

The Unimus backup exporter is a bash script that exports backups from your [Unimus](https://unimus.net) server, stores backups locally, and pushes them to a git repo if desired.

## _Requirements_

The only requirements for this script are `bash`, `curl`, `jq`, and `base64`.

## _How to use the Exporter_ 

Browse to your Unimus directory. This is normally at /opt/unimus. Clone the unimus-backup-exporter repo to a folder called unimus-backup-exporter.

``` bash
cd /opt/unimus
git clone https://path.to.repo/group/repo.git unimus-backup-exporter
```

If you haven't already, create a git repo to store and track your backups.

Browse to the unimus-backup-exporter directory, and clone your backups repo into a folder called backups.

``` bash
git clone https://path.to.repo/group/repo.git backups
```

To configure, make and complete the environment file.

``` bash
cp unimus-backup-exporter.example.env unimus-backup-exporter.env
vi unimus-backup-exporter.env
```

Add the cron to /etc/crontab. Example is 6am.

```
0 6 * * * root /opt/unimus/unimus-backup-exporter/unimus-backup-exporter.sh >/dev/null 2>&1
```

To use the exporter, you must configure the scripts env file with your settings. The script can extract all backups, or just the latest backups depending on configuration. 

If you are using this script to push backups to git, it will create a local git directory based on the settings in your env file, and then push backups to that repo.

* Configure the env with the appropriate variables for your install as described in the Configure File section.

* To execute the script run the following command in the script directory:

``` bash
./unimus-backup-exporter.sh
``` 

After the script runs. You will find your backups nested in a "backup" folder. Backups will be in their own folders, labeled by the Unimus Device ID, and the IP address.

## _Configuration File_

The most basic requirements for the script to operate are.

``` text
|        Setting        |         Value             |
|  -------------------  |  -----------------------  |
| unimus_server_address | "http://192.168.0.1:8085" |
| unimus_api_key        | "your unimus api key"     |
| backup_type           | "all" or "latest"         |
| export_type           | "git" or "fs"             |
``` 

backup_type
 - "all" will download all backups when the script is run
 - "latest" will download only the latest when every time the script is run 
 
export_type
 - "git" will push the backups to your git repo
 - "fs" will keep the backups on the local fs
 
In addition to these basic requirements, using git requires some of these additional requirements.

``` text
|       Setting       |          Value           |
|  -----------------  |  ----------------------  |
| git_username        | "foo"                    |
| git_password        | "bar"                    |
| git_email           | foo@bar.com              |
| git_server_protocal | "http", "https" or "ssh" |
| git_server_address  | "192.168.1.1"            |
| git_port            | "80"                     |
| git_repo_name       | "Foo/Backups.git"        |
| git_branch          | "master"                 |
 ```
 Depending on your git server you may not require a password.
 
 ## _Automating the exporter_
 
 To run your script periodically, the most common solution will be scheduling a cron job. Adding the following line to crontab -e will set up the script to run every night at 3AM
  
``` 
0 3 * * * root /path-to-script/unimus-backup-exporter.sh
```
Note: Using root as your user is not recommended.
