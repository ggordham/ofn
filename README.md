# ofn
Oracle [database] Free Now (OFN) - scripts to automate the install and usage of Oracle database free edition


## onf\_backup.sh

Sample crontab entry.

```
# DB backup scripts - archives every 3 hours
#         full backup saturday, incremental rest of week
2 0,3,6,9,12,15,18,21 * * * /opt/ofn/ofn_bkup.sh --lvl a
2 22 * * 0,1,2,3,4,5 /opt/ofn/ofn_bkup.sh --lvl i
2 22 * * 6 /opt/ofn/ofn_bkup.sh --lvl f
```

### Todo

1. Cleanup old log files
2. send email on failures

