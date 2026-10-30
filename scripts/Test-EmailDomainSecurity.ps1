#Requires -Version 5.1
<#
.SYNOPSIS
    Checks a domain's email authentication records: MX, SPF, DMARC and common DKIM selectors.
.DESCRIPTION
    Read-only DNS lookups with Resolve-DnsName. Flags missing records, SPF "+all" or
    "?all", too many SPF lookups, and DMARC policies of p=none.
.PARAMETER Domain
    One or more domains to check.
.PARAMETER DkimSelector
    DKIM selectors to try (defaults cover Microsoft 365, Google Workspace and common providers).
.EXAMPLE
    .\Test-EmailDomainSecurity.ps1 -Domain example.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)][string[]]$Domain,
    [string[]]$DkimSelector = @('selector1','selector2','google','default','k1','s1','s2','dkim')
)

process {
    foreach ($d in $Domain) {
        $findings = [System.Collections.Generic.List[object]]::new()
        function Add-Finding([string]$Check, [string]$Status, [string]$Detail) {
            $findings.Add([pscustomobject]@{ Domain = $d; Check = $Check; Status = $Status; Detail = $Detail })
        }
        function Get-Txt([string]$Name) {
            Resolve-DnsName -Name $Name -Type TXT -ErrorAction SilentlyContinue |
                Where-Object { $_.Type -eq 'TXT' } | ForEach-Object { $_.Strings -join '' }
        }

        $mx = Resolve-DnsName -Name $d -Type MX -ErrorAction SilentlyContinue | Where-Object Type -eq 'MX'
        if ($mx) { Add-Finding 'MX' 'PASS' (($mx | Sort-Object Preference | ForEach-Object NameExchange) -join ', ') }
        else { Add-Finding 'MX' 'INFO' 'No MX records (domain may not receive mail)' }

        $spf = @(Get-Txt $d | Where-Object { $_ -like 'v=spf1*' })
        if ($spf.Count -eq 0)      { Add-Finding 'SPF' 'FAIL' 'No SPF record' }
        elseif ($spf.Count -gt 1)  { Add-Finding 'SPF' 'FAIL' 'Multiple SPF records (permerror)' }
        else {
            $s = $spf[0]
            $lookups = ([regex]::Matches($s, '\b(include:|a\b|a:|mx\b|mx:|ptr|exists:|redirect=)')).Count
            $status = if ($s -match '[+?]all\b') { 'FAIL' } elseif ($lookups -gt 10) { 'FAIL' } elseif ($s -match '~all') { 'WARN' } elseif ($s -match '-all') { 'PASS' } else { 'WARN' }
            Add-Finding 'SPF' $status ("{0}  (top-level DNS lookups: {1})" -f $s, $lookups)
        }

        $dmarc = @(Get-Txt "_dmarc.$d" | Where-Object { $_ -like 'v=DMARC1*' })
        if ($dmarc.Count -eq 0) { Add-Finding 'DMARC' 'FAIL' 'No DMARC record' }
        else {
            $p = ([regex]::Match($dmarc[0], 'p=(\w+)')).Groups[1].Value
            $status = switch ($p) { 'reject' { 'PASS' } 'quarantine' { 'PASS' } 'none' { 'WARN' } default { 'FAIL' } }
            $rua = if ($dmarc[0] -match 'rua=') { 'reports on' } else { 'no rua reporting' }
            Add-Finding 'DMARC' $status ("p={0}, {1}" -f $p, $rua)
        }

        $dkimHits = foreach ($sel in $DkimSelector) {
            $name = "$sel._domainkey.$d"
            $txt = Get-Txt $name | Where-Object { $_ -match 'p=' }
            $cname = Resolve-DnsName -Name $name -Type CNAME -ErrorAction SilentlyContinue | Where-Object Type -eq 'CNAME'
            if ($txt -or $cname) { $sel }
        }
        if ($dkimHits) { Add-Finding 'DKIM' 'PASS' ("Selectors found: {0}" -f ($dkimHits -join ', ')) }
        else { Add-Finding 'DKIM' 'WARN' 'No common selector found (provider may use a custom selector)' }

        $findings
    }
}
