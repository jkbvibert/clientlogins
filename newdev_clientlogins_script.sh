## Identify Accounts with > 40 different client logins and then lock those accounts
#check to make sure all three parameters are entered
if [ $# -ne 3 ]
then
   echo "< 3 parameters <target dbname> <db hostname> <notice email groups>"
   echo "< 3 parameters <target dbname> <db hostname> <notice email groups>" | mailx -r <team_email> -s "Issue with $0 on $1" <my_email>
   exit 1
fi

#set the entered parameters to variables
export DBNAME=$1
export HOSTNM=$2

export VSQL="/opt/vertica/bin/vsql -U <service_account_username> -w <password> -d $DBNAME -h $HOSTNM -P footer=off -p 5433"
EMAIL_FROM="<team_email>"
EMAIL_TO="<my_email>"
export SCRDIR=/home/srvc_bds_tidal/vertica/mnt_scripts_daily

#get output for whether database is up or not
$VSQL << EOF
\o /tmp/node_status.out
select node_name, node_address, node_state from nodes;
\o
\q
EOF

## validate if database is exist and up running
if [ $? -ne 0 ] #$? means exist status of last command executed
then
   echo "Some error occurred when checking \"select node_name, node_address, node_state from nodes;\". \nIt likely did not complete successfully." | mailx -r <team_email> -s "Not able to connect to DB $2" <my_email>
   exit 1
fi

export DBNAME=`cat /tmp/node_status.out | grep "^ v_" | head -1 | awk '{print $1}'|cut -d"_" -f2-|rev|cut -d"_" -f2-|rev`

if [ $1 != $DBNAME ]
then
   echo "The db name entered in the command did not match the db name in the \"nodes\" table" | mailx -r <team_email> -s "Not able to connect to DB $2" <my_email>
   exit 1
fi

ssh <username>@$HOSTNM << EOF
pbrun su - vertica -c "/opt/vertica/bin/vsql -t -c \"select 'alter user '||user_name||' account lock;' from (select user_name, count(user_name) as login_count from (select user_name, substring(client_hostname,1,instr(client_hostname,':')-1) as client_hostname from  hp_metrics.user_sessions where user_name <> 'vertica' group by 1,2) a group by 1) b where login_count > 40;\" | /usr/bin/tee /home/vertica/newdev_clientlogins_input.txt"
pbrun su - vertica -c "/bin/sed -i '$d' /home/vertica/newdev_clientlogins_input.txt" #remove the last line of the file
pbrun su - vertica -c "/bin/sed -i -e 's/^.//' /home/vertica/newdev_clientlogins_input.txt" #remove the random space at the beginning of each line
pbrun su - vertica -c "/opt/vertica/bin/vsql -f /home/vertica/newdev_clientlogins_input.txt | tee /home/vertica/newdev_clientlogins_erroroutput.txt" #run the input file as vsql commands and output to a txt file
EOF

rm /tmp/node_status.*
