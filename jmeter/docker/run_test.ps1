param(
    [Parameter(Mandatory=$true)]
    [string]
    $tenant,
    # Name of test
    [Parameter(Mandatory=$true)]
    [string]
    $TestName,
    # Where to put the report directory
    [Parameter(Mandatory=$true)]
    [string]
    $ReportFolder
)
$CurrentPath = Split-Path $MyInvocation.MyCommand.Path -Parent

Set-Location $CurrentPath
$MasterPod = $(kubectl -n $tenant get pods --selector=jmeter_mode=master --no-headers=true --output=name).Replace("pod/","")
kubectl cp $TestName $tenant/${MasterPod}:"/$(Split-Path $TestName -Leaf)"
kubectl -n $tenant exec $MasterPod -- /load_test_run "/$(Split-Path $TestName -Leaf)"
kubectl cp $tenant/${MasterPod}:/report $ReportFolder
kubectl cp $tenant/${MasterPod}:/results.log $ReportFolder