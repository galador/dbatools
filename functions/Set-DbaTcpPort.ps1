Function Set-DbaTcpPort {
<#
.SYNOPSIS
Changes the TCP port used by the specified SQL Server.
	
.DESCRIPTION
This function changes the TCP port used by the specified SQL Server. 
		
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER IPAddress
Wich IPAddress should the portchange , if omitted allip (0.0.0.0) will be changed with the new portnumber. 

.PARAMETER Port
TCPPort that SQLService should listen on.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Set-DbaTcpPort

.EXAMPLE
Set-DbaTcpPort -SqlServer sqlserver2014a -Port 1433

Sets the port number 1433 for allips on the default instance on sqlserver2014a

.EXAMPLE
Set-DbaTcpPort -SqlServer winserver\sqlexpress -IpAddress 192.168.1.22 -Port 1433

Sets the port number 1433 for IP 192.168.1.22 on the sqlexpress instance on winserver	

.EXAMPLE
Set-DbaTcpPort -sqlserver 'SQLDB2014A' ,'SQLDB2016B' -port 1337

Sets the port number 1337 for ALLIP's on sqlserver SQLDB2014A and SQLDB2016B
#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[Alias("SqlCredential")]
		[PsCredential]$Credential,
		[parameter(Mandatory = $true)]
		[ValidateRange(1, 65535)]
		[int]$Port,
		[ipaddress[]]$IpAddress = '0.0.0.0',
		[switch]$Silent
	)
	process {
		
		foreach ($instance in $SqlInstance) {
			try {
				$server = Connect-SqlServer -SqlServer "TCP:$instance" -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -InnerErrorRecord $_ -Target $instance -Continue
			}
			
			if ($server.VersionMajor -lt 9) {
				Stop-Function -Message "SQL Server not supported" $_ -Target $instance -Continue
			}
			
			$instancename = $server.instanceName
			
			if (!$instancename) {
				$instancename = 'MSSQLSERVER'
			}
			
			if ($server.IsClustered) {
				Write-Message -Level Verbose -Message "Instance is clustered fetching nodes..."
				$clusterquery = "select nodename from sys.dm_os_cluster_nodes where not nodename = '$($server.ComputerNamePhysicalNetBIOS)'"
				$clusterresult = $server.ConnectionContext.ExecuteWithResults("$clusterquery")
				foreach ($row in $clusterresult.tables[0].rows) { $ClusterNodes += $row.Item(0) + " " }
				Write-Warning "$instance is a clustered instance, portchanges will be reflected on other nodes ( $clusternodes) after a failover..."
			}
			$scriptblock = {
				$instance = $args[0]
				$instancename = $args[1]
				$port = $args[2]
				$ipaddress = $args[3]
				$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $instance
				$instance = $wmi.ServerInstances | Where-Object { $_.Name -eq $instancename }
				$tcp = $instance.ServerProtocols | Where-Object { $_.DisplayName -eq 'TCP/IP' }
				$ipaddress = $tcp.IPAddresses | where-object { $_.IPAddress -eq $ipaddress }
				$tcpport = $ipaddress.IPAddressProperties | Where-Object { $_.Name -eq 'TcpPort' }
				try {
					$tcpport.value = $port
					$tcp.Alter()
				}
				catch {
					return $_
				}
			}
			try {
				$instanceNI = $instance.split("\")[0]
				$resolved = Resolve-DbaNetworkName -ComputerName $instanceNI -Verbose:$false
				Write-Message -Level Verbose -Message "Writing TCPPort $port for $instance to $($resolved.FQDN)..."
				$setport = Invoke-ManagedComputerCommand -Server $resolved.FQDN -ScriptBlock $scriptblock -ArgumentList $Server.NetName, $instancename, $port, $ipaddress
				if ($setport.length -eq 0) {
					if ($ipaddress -eq '0.0.0.0') {
						Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: ALLIP's PORT: $port"
					}
					else {
						Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: $ipaddress PORT: $port"
					}
				}
				else {
					if ($ipaddress -eq '0.0.0.0') {
						Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: ALLIP's PORT: $port" -NoNewline
						Write-Message -Level Output -Message " FAILED!" -ForegroundColor Red
					}
					else {
						Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: $ipaddress PORT: $port" -NoNewline
						Write-Message -Level Output -Message " FAILED!" -ForegroundColor Red
					}
				}
			}
			catch {
				try {
					Write-Message -Level Verbose -Message "Failed to write TCPPort $port for $instance to $($resolved.FQDN) trying computername $($server.ComputerNamePhysicalNetBIOS)...."
					$setport = Invoke-ManagedComputerCommand -Server $server.ComputerNamePhysicalNetBIOS -ScriptBlock $scriptblock -ArgumentList $Server.NetName, $instancename, $port, $ipaddress
					if ($setport.length -eq 0) {
						if ($ipaddress -eq '0.0.0.0') {
							Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: ALLIP's PORT: $port"
						}
						else {
							Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: $ipaddress PORT: $port"
						}
					}
					else {
						if ($ipaddress -eq '0.0.0.0') {
							Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: ALLIP's PORT: $port" -NoNewline
							Write-Message -Level Output -Message " FAILED!" -ForegroundColor Red
						}
						else {
							Write-Message -Level Output -Message "SQLSERVER: $instance IPADDRESS: $ipaddress PORT: $port" -NoNewline
							Write-Message -Level Output -Message " FAILED!" -ForegroundColor Red
						}
					}
				}
				catch {
					Stop-Function "Could not update TCP port for $instance"
				}
			}
			
		}
	}
}