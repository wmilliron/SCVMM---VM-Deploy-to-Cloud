Function Deploy-SCVMSimple
{
    [CmdletBinding()]
    Param(
        [String]$VMName,
        [String]$cloud,
        [String]$Template
        )

    $TemplateObj = Get-SCVMTemplate -All | where { $_.Name -eq $Template }
    $virtualMachineConfiguration = New-SCVMConfiguration -VMTemplate $TemplateObj -Name $VMName
    $cloudObj = Get-SCCloud -Name $cloud

    Write-Verbose "Creating VM $VMName in cloud $cloud"
    New-SCVirtualMachine -Name $VMName -VMConfiguration $virtualMachineConfiguration -Cloud $cloudObj -Computername $VMName| out-null

    #return object
    Get-SCVirtualMachine -name $VMName
}


Deploy-SCVMSimple -VMName "TestComputer9" -cloud "VDI Computers" -Template "VDI Template V2" -Verbose
