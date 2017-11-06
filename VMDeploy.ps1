<#
.SYNOPSIS
    When provided with a valid CSV, this script will deploy the VMs in the CSV to the VMM Cloud specified according to the provided parameters.
    The script will also rename the VHDXs to include the name of the VM, instead of just the name from the template.
.DESCRIPTION
    Prerequisites:
        1. Powershell 4.0
        2. VirtualMachineManager module installed, with proper privileges to the VMM server.
    Assumptions:
        1. The templates referenced from VMM include 3 VHDs; the first being the OS, second being pagefile, third being app - Edit designated sections for alterations
        2. This script assumes each 'Cloud' uses a separate vmswitch, edit the names of those virtual swithces accordingly.
        3. The combined build time of all virtual machines is less than 4 hours. The cleanup phase starts after all jobs complete, or 4 hours - whichever comes first.

.PARAMETER PathtoCSV
    Required parameter. Full or relative path to csv file that includes fields: VMName, Template, Cloud, NameofComputer,Description,VMNetwork, OS,
    CPUs, StartupMem, MinimumMem, and MaximumMem. CSV Provided in Repo
.EXAMPLE
    Usage: VMDeploy.ps1 -PathtoCSV "C:\VMsToCreate.csv"
.NOTES
    Author: wmilliron
    Date: 11/3/2017
#>

[CmdletBinding()]
Param([Parameter(Mandatory=$True,Position=1)][String]$PathtoCSV)
Import-Module virtualmachinemanager -ErrorAction Stop
Clear-Host
Write-Host "Provided path to CSV: $PathtoCSV"
$VMs = Import-Csv -Path $PathtoCSV -ErrorAction Stop

    foreach ($VM in $VMs){
        #Variables
        $VMName = $VM.VMName
        $TemplateObj = Get-SCVMTemplate -All | where { $_.Name -eq $VM.Template }
        $cloudObj = Get-SCCloud -Name $VM.Cloud
        $ComputerIdentity = $VM.NameOfComputer
        $Description = $VM.Description
        $Network = $VM.VMNetwork
        $OS = $VM.OS
        $HWJobID = [System.Guid]::NewGuid().ToString()
        $VMJobID = [System.Guid]::NewGuid().ToString()
        $VMNetwork = Get-SCVMNetwork -VMMServer scvmm -Name "$Network"

        ###EDIT FOR NUMBER/NAME OF VOLUMES FROM VMM TEMPLATE###
        $OSVol = "$VMName" + "_os"
        $PagefileVol = "$VMName" + "_pagefile"
        $AppsVol = "$VMName" + "_apps"
        #######################################################

        ###EDIT FOR NAMES OF VMSWITCH IN EACH CLOUD###
        if ($VM.Cloud -like "*Cluster1*")
        {
            $vmswitch = "Cluster1_LogicalSW"
        }
        elseif ($VM.Cloud -like "*Cluster2*")
        {
            $vmswitch = "Cluster2_LogicalSW"
        }
        ###############################################

        #Define Hardware Parameters, and loads into HW profile for temporary template
                
        New-SCVirtualScsiAdapter -VMMServer scvmm -JobGroup $HWJobID -AdapterID 7 -ShareVirtualScsiAdapter $false -ScsiControllerType DefaultTypeNoType 
        New-SCVirtualDVDDrive -VMMServer scvmm -JobGroup $HWJobID -Bus 0 -LUN 1
        New-SCVirtualNetworkAdapter -VMMServer scvmm -MACAddress "00:00:00:00:00:00" -MACAddressType Static -VirtualNetwork $vmswitch -Synthetic -EnableVMNetworkOptimization $false -EnableMACAddressSpoofing $false -EnableGuestIPNetworkVirtualizationUpdates $true -IPv4AddressType Dynamic -IPv6AddressType Dynamic -VMNetwork $VMNetwork -DevicePropertiesAdapterNameMode Disabled -JobGroup $HWJobID
                
        $CPUType = Get-SCCPUType -VMMServer scvmm | where {$_.Name -eq "3.60 GHz Xeon (2 MB L2 cache)"}
                
        New-SCHardwareProfile -VMMServer scvmm -CPUType $CPUType -Name "HWProfile_$VMName" -CPUCount $VM.CPUs -MemoryMB $VM.StartupMem -DynamicMemoryEnabled $true -DynamicMemoryMinimumMB $VM.MinimumMem -DynamicMemoryMaximumMB $VM.MaximumMem -DynamicMemoryBufferPercentage 20 -MemoryWeight 5000 -CPUExpectedUtilizationPercent 20 -DiskIops 0 -CPUMaximumPercent 100 -CPUReserve 0 -NumaIsolationRequired $false -NetworkUtilizationMbps 0 -CPURelativeWeight 100 -HighlyAvailable $true -HAVMPriority 2000 -DRProtectionRequired $false -SecureBootEnabled $true -SecureBootTemplate "MicrosoftWindows" -CPULimitFunctionality $false -CPULimitForMigration $true -CheckpointType Standard -Generation 2 -JobGroup $HWJobID
                
        #Take the provided template from the csv, and combine it with other provided parameters to create a temporary template
                
        $HardwareProfile = Get-SCHardwareProfile -VMMServer scvmm | where {$_.Name -eq "HWProfile_$VMName"}
        $OperatingSystem = Get-SCOperatingSystem -VMMServer scvmm | where {$_.Name -eq "$OS"}
                
        New-SCVMTemplate -Name "TemporaryTemplate_$VMName" -Template $TemplateObj -HardwareProfile $HardwareProfile -ComputerName "$ComputerIdentity" -TimeZone 35 -Workgroup "WORKGROUP" -AnswerFile $null -OperatingSystem $OperatingSystem -JobGroup $VMJobID
                
        #With new template generated, this section creates a VMConfiguration for the new VM based on the temporary template info
                
        $template = Get-SCVMTemplate -All | where { $_.Name -eq "TemporaryTemplate_$VMName" }
        $virtualMachineConfiguration = New-SCVMConfiguration -VMTemplate $template -Name "$VMName"
        Write-Output $virtualMachineConfiguration

        Set-SCVMConfiguration -VMConfiguration $virtualMachineConfiguration -Cloud $cloudObj
        Update-SCVMConfiguration -VMConfiguration $virtualMachineConfiguration
        
        $AllNICConfigurations = Get-SCVirtualNetworkAdapterConfiguration -VMConfiguration $virtualMachineConfiguration
        
        ###EDIT THIS SECTION IF YOU CHANGED THE VHD VARIABLES ABOVE###
        #This section modifies the VMConfig so the VHD names match that of the VM itself
        $VHDConfiguration = Get-SCVirtualHardDiskConfiguration -VMConfiguration $virtualMachineConfiguration
        $VHDConfiguration = $VHDConfiguration[0]
        Set-SCVirtualHardDiskConfiguration -VHDConfiguration $VHDConfiguration -PinSourceLocation $false -PinDestinationLocation $false -FileName "$OSVol" -StorageQoSPolicy $null -DeploymentOption "UseNetwork"
        $VHDConfiguration = Get-SCVirtualHardDiskConfiguration -VMConfiguration $virtualMachineConfiguration
        $VHDConfiguration = $VHDConfiguration[1]
        Set-SCVirtualHardDiskConfiguration -VHDConfiguration $VHDConfiguration -PinSourceLocation $false -PinDestinationLocation $false -FileName "$PagefileVol" -StorageQoSPolicy $null -DeploymentOption "UseNetwork"
        $VHDConfiguration = Get-SCVirtualHardDiskConfiguration -VMConfiguration $virtualMachineConfiguration
        $VHDConfiguration = $VHDConfiguration[2]
        Set-SCVirtualHardDiskConfiguration -VHDConfiguration $VHDConfiguration -PinSourceLocation $false -PinDestinationLocation $false -FileName "$AppsVol" -StorageQoSPolicy $null -DeploymentOption "UseNetwork"
        ##############################################################
        
        Update-SCVMConfiguration -VMConfiguration $virtualMachineConfiguration
                
        #Creates the VM will all provided parameters
        New-SCVirtualMachine -Name "$VMName" -VMConfiguration $virtualMachineConfiguration -Description "$Description" -Cloud $cloudObj -BlockDynamicOptimization $false -ReturnImmediately -StartAction "NeverAutoTurnOnVM" -StopAction "SaveVM" -JobGroup $VMJobID -Verbose
    }

#Cleanup

$Sleeper = 0
Do{
    Start-sleep 60
    $Sleeper += 1
}
Until((get-scjob -Running) -eq $null -or $Sleeper -eq 240)
if($Sleeper -eq 240){
    write-host "Cleanup Job Timed out after 4 hours" -ForegroundColor Red
    return
}
elseif((get-scjob -Running) -eq $null){
    foreach ($VM in $VMs){
        $VMName = $VM.VMName
        $HardwareProfile = Get-SCHardwareProfile -VMMServer scvmm -Name "HWProfile_$VMName"
        Remove-SCVMTemplate -vmtemplate "TemporaryTemplate_$VMName"
        Remove-SCHardwareProfile -HardwareProfile "HWProfile_$VMName"
    }
    write-host "Cleanup Complete" -ForegroundColor Green
    return
}