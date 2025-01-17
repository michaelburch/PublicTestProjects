<#
    .SYNOPSIS
    Executes JMeter performance tests on an AKS cluster.

    .DESCRIPTION
    The run_test.ps1 script provides a highly flexible method to execute JMeter performance scripts.
    It will produce a JMeter dashboard report in a uniquely named folder in the current working directory.
    After the test has completed the JMeter test rig is deleted.

    .PARAMETER Tenant
    Theoretically this allows for multiple concurrent jmeter deployments on a common AKS cluster.  Please note
    that this feature has not been functionally tested yet.

    .PARAMETER TestName
    The name of the JMeter test to be executed.

    .PARAMETER ReportFolder
    A folder name will be automatically created.  You have the option of providing a folder name if desired.

    .PARAMETER DeleteTestRig
    This is used for debugging purposes.  If you want to keep the test rig around so you can inspect the current state of the test rig pods you can.  

    .PARAMETER UserProperties
    If you would like to customize the JMeter dashboard report you can provide a custom user.properties file.  There is an example user.properties file
    in the folder above where these scripts are located.
    
    .PARAMETER RedisScript
    For high performance and scaleable parameters it is recommended to use Redis cache.  

    .PARAMETER ExecuteOnceOnMaster
    Sometimes there is a need to setup test runs and trying to coordinate across several test slaves to only do things 1 time is difficult. This Provides the ability to execute a test script 1 time per test run on the Master Node.
    * You can can initialize stuff and not have to worry about concurrence
    * The same JMX is used to initialize and run the performance test
    * A JMeter command line parameter of -JMaster=true is added so that your JMeter script can use an "If Controller" to modify how it acts on the master node.
    * No slaves start executing until after the JMX script has completed on the Master node.

    .PARAMETER GlobalJmeterParams
    JMeter supports global parameters by adding -GParameterName=Some Value which will be set as a parameter on the test rig master and slaves.
    * This feature allows for any number of "-G" parameters to be added.
    * This feature also allows you to add any other JMeter option you want to assuming it's not already present.
    
    .INPUTS
    None.  You cannot pipe objects to run_test.ps1

    .EXAMPLE
    PS> .\run_test.ps1 -tenant jmeter -TestName ..\drparts.jmx -UserProperties ..\user.properties

    .LINK 
    JMeter If Controller: https://jmeter.apache.org/usermanual/component_reference.html#If_Controller
    JMeter test Rigs: https://jmeter.apache.org/usermanual/remote-test.html

#>


param(
    [Parameter(Mandatory=$true)]
    [string]
    $tenant,
    # Name of test
    [Parameter(Mandatory=$true)]
    [string]
    $TestName,
    # Where to put the report directory
    [Parameter(Mandatory=$false)]
    [string]
    $ReportFolder="$(get-date -Format FileDateTimeUniversal)results",
    [Parameter(Mandatory=$false)]
    [bool]
    $DeleteTestRig = $true,
    [Parameter(Mandatory=$false)]
    [string]
    $UserProperties="",
    [Parameter(Mandatory=$false)]
    [string]
    $RedisScript="",
    [Parameter(Mandatory=$false)]
    [bool]
    $ExecuteOnceOnMaster=$false,
    [parameter(ValueFromRemainingArguments=$true)]
    [string[]]
    $GlobalJmeterParams
)
#$JmeterVersion=5.2.1
$CurrentPath = Split-Path $MyInvocation.MyCommand.Path -Parent

Set-Location $CurrentPath
if($null -eq $(kubectl -n $tenant get pods --selector=jmeter_mode=master --no-headers=true --output=name) )
{
    Write-Error "Master pod does not exist"
    exit
}
$MasterPod = $(kubectl -n $tenant get pods --selector=jmeter_mode=master --no-headers=true --output=name).Replace("pod/","")
Write-Output "Checking for user properties"
if(!($UserProperties -eq $null -or $UserProperties -eq "" ))
{
    Write-Output "Copying user.properties over"
    kubectl cp $UserProperties $tenant/${MasterPod}:/jmeter/apache-jmeter-5.3/bin/user.properties
}
Write-Output "Checking for Redis script"
if(!($RedisScript -eq $null -or $RedisScript -eq ""))
{
    #Since we use helm to install Redis we can assume the pod name for the first redis slave instance
    write-output "Executing redis script"
    Get-Content $RedisScript | kubectl -n $tenant exec -i jmeterredis-master-0 -- redis-cli --pipe
}
Write-Output "Processing global parameters"
[string]$GlobalParmsCombined=" "
foreach($gr in $GlobalJmeterParams)
{
    $GlobalParmsCombined += $gr + " "

}
Write-Output "Copying test plan to aks"
kubectl cp $TestName $tenant/${MasterPod}:"/$(Split-Path $TestName -Leaf)"
if($ExecuteOnceOnMaster)
{
    Write-Output "Starting optional execution of jmx on the master node"
    kubectl -n $tenant exec $MasterPod -- jmeter -n -t "/$(Split-Path $TestName -Leaf)" -JMaster=true $GlobalJmeterParams
}
Write-Output "Starting test execution on AKS Cluster"

kubectl -n $tenant exec $MasterPod -- /load_test_run "/$(Split-Path $TestName -Leaf)" $GlobalJmeterParams
Write-Output "Retrieving dashboard, results and Master jmeter.log"
kubectl cp $tenant/${MasterPod}:/report $ReportFolder
kubectl cp $tenant/${MasterPod}:/results.log $ReportFolder/results.log
kubectl cp $tenant/${MasterPod}:/jmeter/apache-jmeter-5.3/bin/jmeter.log $ReportFolder/jmeter.log
if($DeleteTestRig)
{
    $result = .\Set-JmeterTestRig.ps1 -tenant $tenant -ZeroOutTestRig $true
   
}