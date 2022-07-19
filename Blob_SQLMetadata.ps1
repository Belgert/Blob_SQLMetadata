## Script Applies Metadata to Blob Storage ##
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## Creating Metadata dataset ##
$servers = "server01", "server02"
$metadata = @()

Function Get-Data {
    $metadata = @()
    Foreach($semester in $semesters) {
        $datbaseName = $database+$semester;
        $pathBase = "C:\export\";
        Write-Host "`nGathering data from $databaseName...." -ForegroundColor Green
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = "Server=$($server);Database=$($datbaseName);Integrated Security=True"

        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand

        $queryText = "
/*GET METADATA FOR BLOB STORAGE */
SELECT DISTINCT 
RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(STUFF(FullUrl, PATINDEX('%[0-9][0-9][0-9][0-9][0-9]%', FullUrl), 12, REPLACE(SUBSTRING(W.Description, 0, dbo.CHARINDEX2('|', W.Description, 1)), '/', ' ')), 'Graduate/', ''), 'ST:', 'ST'), 'coad/', ''), ':', ' -'), '/_w', ''), '.', '')) as DirName,
LTRIM(RTRIM(SUBSTRING(W.Description, 0, dbo.CHARINDEX2(':', W.Description, 1)))) as CourseID,
LTRIM(RTRIM(REPLACE(PARSENAME(REPLACE(REPLACE(SUBSTRING(W.Description, dbo.CHARINDEX2(':', W.Description, 1) +1, LEN(W.Description)), '.', ''),'|', '.'), 3), ':', ' '))) as CourseTitle,
LTRIM(RTRIM(PARSENAME(REPLACE(REPLACE(W.Description, '|', '.'), 'ó', 'o'), 2))) as Instructor,
LTRIM(RTRIM(STUFF(PARSENAME(REPLACE(W.Description, '|', '.'), 1), 6, 7, ''))) as Year,
LTRIM(RTRIM(STUFF(PARSENAME(REPLACE(W.Description, '|', '.'), 1), 1, 5, ''))) as Semester
--
FROM [dbo].[AllDocs] AD
JOIN dbo.AllWebs W ON AD.WebId = W.Id
--
WHERE DirName NOT LIKE '%/Assignment %' 
AND DirName NOT LIKE '%/Forms'
AND DirName NOT LIKE '%/_t'
AND DirName NOT LIKE '%/m'
AND DirName NOT LIKE '%/Drop Off Library'
AND DirName NOT LIKE '%/Lists%'
AND DirName NOT LIKE '%/_catalog%'
AND FullUrl LIKE '%/[0-9][0-9][0-9][0-9][0-9]%'
AND LeafName <> '_t' AND LeafName <> '_w' 
AND Type = 1
"

        $SqlCmd.CommandText = $queryText
        $SqlCmd.Connection = $SqlConnection
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
        $SqlAdapter.SelectCommand = $SqlCmd
        $dataSet = New-Object System.Data.DataSet
        $SqlAdapter.Fill($dataSet)
        $SqlConnection.Close()

        $data = $dataSet.Tables[0]
        Foreach($row in $data) {
            $metadata += New-Object -TypeName psobject -Property @{'DirName' = $row.DirName; 'CourseID' = $row.CourseID; 'CourseTitle' = $row.CourseTitle; 'Instructor' = $row.Instructor; 'Year' = $row.Year; 'Semester' = $row.Semester;}
        } 
    }
    Return $metadata
}

Write-Host "`nGathering data from SQL Servers...." -ForegroundColor Green

Foreach($server in $servers) {
    If($server -eq "server01") {
        $database = "database_root_name01_"
        $semesters = "2014", "2014F", "2014S", "2015F", "2015S", "2016F", "2016S", "2017S", "2017U"
        $metadata += Get-Data
    }
    Else {
        $database = "database_root_name02_"
        $semesters = "2017Fall", "2017Summer", "2018Fall", "2018Spring", "2018Summer", "2019Fall", "2019Spring", "2020Fall", "2020Spring", "2021Fall", "2021Spring", "2022Spring"
        $metadata += Get-Data
    }
}

## Apply Metadata to Blob Storage ##
$folder = "Insert desired save folder location" 
$file = "course.txt"
$container = "blob container name"  
$context = New-AzStorageContext -StorageAccountName "blobStorageAccountName" -StorageAccountKey "StorageAccountKey" 
$blobs = Get-AzStorageBlob -Blob * -Container $container -Context $context | Select-Object @{n = 'blobs'; e = {$_.Name.Substring(0, $_.Name.IndexOf($_.Name.Split("/")[3]) -1)}} -Unique

## Create txt file if not found ##
If(-not(Test-Path -Path $folder$file -PathType Leaf)) {
    New-Item -Path $folder -Name $file }

## Update metadata or tags? (If you want to update everything choose to update metadata ##
$updateTag = Read-Host("`nOverwrite all tags ONLY (Y/N)?")
    While($updateTag -ne $null) {
        If($updateTag -eq "Y") {
            Break
        }
        ElseIf($updateTag -eq "N") {
            #Overwrite All? Useful if error with information used in metadata or tags
            $updateAll = Read-Host("`nOverwrite all metadata and tags (Y/N)?")
            While($updateAll -ne $null) {
                If($updateAll -eq "Y") {
                    Break
                }
                ElseIf($updateAll -eq "N") {
                    Break
                }
                Else {$updateAll = Read-Host("Please enter either ""Y"" for yes or ""N"" for no.")}
            }
        Break
        }
        Else {
            $updateTag = Read-Host("Please enter either ""Y"" for yes or ""N"" for no.")
        }
    }

#If blob has no txt file ##
If(($updateAll -eq "N") -and ($updateTag -eq "N")){
    $blobsTxt = Get-AzStorageBlob -Blob * -Container $container -Context $context | Where-Object {$_.Name -like "*course.txt*"} | Select-Object -ExpandProperty Name 
    $blobs = $blobs.blobs | Where-Object -FilterScript {$_ -notin $blobsTxt.Replace("/course.txt", '')} 

    Foreach($blob in $blobs) {
        ForEach($row in $metadata) {            
            $DirName = $row.DirName

            If($DirName -like '*/*/*/*') {
                $DirName = $DirName.Replace($DirName.Split("/")[2]+"/", '')
            }

            If($DirName -eq $blob) {
                Write-Host "`n$blob match $DirName" -ForegroundColor Green        
                $tag = @{
                    "IsCourse" = "True"
                    "Year" = $row.Year
                    "Semester" = $row.Semester}

                $data = @{
                    "CourseID" =  $row.CourseID
                    "CourseTitle" = $row.CourseTitle
                    "Instructor" = $row.Instructor
                    "Year" = $row.Year
                    "Semester" = $row.Semester}
                    
                Set-AzStorageBlobContent -File $folder$file -Container $container -Metadata $data -Tag $tag -Blob "$blob/$file" -Context $context -Force
            }
        }
    }
}

## Overwrite metadata and tags ##
If($updateAll -eq "Y"){
ForEach($blob in $blobs.blobs){
    ForEach($row in $metadata) {
        $DirName = $row.DirName
        
        If($DirName -like '*/*/*/*') {
            $DirName = $DirName.Replace($DirName.Split("/")[2]+"/", '')
            }
        
        If($blob -eq $DirName) {
            "$blob match $DirName"

            $data = @{
                "CourseID" =  $row.CourseID
                "CourseTitle" = $row.CourseTitle
                "Instructor" = $row.Instructor
                "Year" = $row.Year
                "Semester" = $row.Semester}

            $tag = @{
                "IsCourse" = "True"
                "Year" = $row.Year
                "Semester" = $row.Semester}
            
            $newBlob = "$blob/" + "$file"
            Set-AzStorageBlobContent -File $folder$file -Container $container -Metadata $data -Tag $tag -Blob $newBlob -Context $context -Force
        }
    }
}
}

## Update tags only ##
If($updateTag -eq "Y"){
Foreach($blob in $blobs.blobs) {
    ForEach($row in $metadata) {
        $DirName = $row.DirName

        If($DirName -like '*/*/*/*') {
            $DirName = $DirName.Replace($DirName.Split("/")[2]+"/", '')
            }

        If($blob -eq $DirName) {
            $newBlob = "$blob/" + "$file"
            Set-AzStorageBlobTag -Container $container -Blob $newBlob -Tag @{"IsCourse" = "True"; "Year" = $row.Year; "Semester" = $row.Semester} -Context $context -Confirm:$false
        }
    }
}
}