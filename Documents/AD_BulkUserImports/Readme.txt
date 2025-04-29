==================================================================================
Title        : Bulk Active Directory User Creation Script
Module       : Create-ADUserBulk.ps1
Author       : Akhilesh Ayyagari
Copyright    : © 2024 Akhilesh Ayyagari. All rights reserved.
==================================================================================

Overview:
---------
This script allows you to bulk create Active Directory users from a CSV file.
It ensures professional reporting of successes and failures, with safe error handling.

Requirements:
--------------
- PowerShell 5.1+
- ActiveDirectory module installed (via RSAT or server roles)
- Permissions to create users in Active Directory
- The OU must already exist in Active Directory before running the script.

Folder Structure:
------------------
Default location for importing CSV:
C:\Users\<YourUsername>\Documents\AD_BulkUserImports\NewUsers.csv

If the AD_BulkUserImports folder doesn't exist, it will be created automatically.

CSV Template (Fields Required):
---------------------------------
Name,SamAccountName,Password,OU,Department,Title

Example CSV content:

Name,SamAccountName,Password,OU,Department,Title
John Doe,jdoe,P@ssw0rd123,OU=Users,DC=yourdomain,DC=com,IT Department,Systems Engineer
Jane Smith,jsmith,P@ssJane123,OU=Users,DC=yourdomain,DC=com,Finance,Accountant

Running the Script:
--------------------
1. Open PowerShell as Administrator.
2. Navigate to the folder where Create-ADUserBulk.ps1 is saved.
3. Run the script:

    .\Create-ADUserBulk.ps1

4. When prompted:
    - Choose to use the default CSV path or specify a custom path.
5. Users will be created automatically.
6. Success and failure reports will be generated in:

    C:\Users\<YourUsername>\Documents\AD_BulkUserImports\

Files Generated:
-----------------
- SuccessReport_<timestamp>.txt → List of users created successfully
- FailureReport_<timestamp>.txt → List of users that failed with error details

Support:
---------
For any issues or customization requests, contact the script author: Akhilesh Ayyagari.

License:
---------
This script is the intellectual property of Akhilesh Ayyagari.
Unauthorized copying, distribution, or modification is prohibited.

==================================================================================
