# cloneDB
Scan Jira for special issue and clone MySQL database

Main ideas:
* scanIssues4cloneDB.sh scans Jirra for new issues in project "new enaminestore" that assign to me, have "TO DO" state and summary containes "[DB] "
* If it found, than every issue transit ti "IN PROGRESS" state, every summary split to string array using space as delimiter and 3th word assumes as db names list with comma or space as delimiter
* start db dump
* drop if exists every target db and import it from dump
* If there aren't any errors, all issues transited to "DONE" state 
