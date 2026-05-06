#!/bin/bash
#Do not forget to give execute permissions on this shell script: chmod 775 rman_node_check.sh
# Desc : check if the instance is primary or not understand active or not

#Remark: Because of a shared storage account between the primary and standby nodes I have added the hostname in the log message to indicate which server has logged what
LogDir=/appli/oracle/backup/$1/log
LogFile=/appli/oracle/backup/$1/log/rman_node_check_$1.log
mkdir -p ${LogDir}
HostName=`hostname`
export ORACLE_SID=$1
export ORAENV_ASK=NO
. oraenv

# Connect to Oracle and run the SQL query to get the current database role
sql_output=$(sqlplus -S "/ as sysdba" << EOF
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING OFF
SET PAGESIZE 5000
SET LINESIZE 9999
SELECT UPPER(DATABASE_ROLE) AS DATABASE_ROLE FROM V\$DATABASE;
EXIT
EOF
)

#SQL result has a leading carriage return, remove it
sql_output=`echo $sql_output`
echo "Local database role of $1 is $sql_output"

#Check if SQL query execution was successful
if [ $? -eq 0 ]; then
    #Check database role
    if [ "$sql_output" == "PRIMARY" ]; then
       echo "$(date "+ %d/%m/%Y %H:%M:%S") - $HostName - $1 - Local database role is $sql_output, is OK, node can start RMAN backup" >> $LogFile
       exit 0
    else
      if [ "$sql_output" == "PHYSICAL STANDBY" ]; then
        echo "$(date "+ %d/%m/%Y %H:%M:%S") - $HostName - $1 - Local database role is $sql_output, is NOK, node can not start RMAN backup" >> $LogFile
        exit 1
      else
        echo "$(date "+ %d/%m/%Y %H:%M:%S") - $HostName - $1 - Local database role $sql_output is unexpected, is NOK, node can not start RMAN backup" >> $LogFile
        exit 1
      fi
    fi
else
    echo "$(date "+ %d/%m/%Y %H:%M:%S") - $HostName - $1 - Error: SQL query execution failed: $?" >> $Logfile
    exit 1
fi

