#Requires -Version 5.1
<#
.SYNOPSIS
    Measures sequential write and read throughput to a local folder or UNC share.
.DESCRIPTION
    Writes a test file in fixed-size blocks with write-through (no OS write cache), reads it
    back, reports MB/s and Mbit/s, and deletes the file. Reads can be served from cache on the
    machine under test; use a file larger than its RAM for cold-read numbers. Useful for comparing a
    Hyper-V host's disks, a NAS share, or a client's path to a file server.
.PARAMETER Path
    Folder to test, for example D:\ or \\fileserver\share.
.PARAMETER SizeMB
    Test file size (default 1024 MB).
.PARAMETER BlockKB
    Block size (default 1024 KB).
.PARAMETER Runs
    Number of runs to average (default 3).
.EXAMPLE
    .\Test-StorageThroughput.ps1 -Path \\fileserver\share -SizeMB 2048
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(16, 65536)][int]$SizeMB = 1024,
    [ValidateRange(4, 65536)][int]$BlockKB = 1024,
    [ValidateRange(1, 20)][int]$Runs = 3
)

if (-not (Test-Path $Path)) { throw "Path not found: $Path" }
$file = Join-Path $Path ("throughput-test-{0}.bin" -f [guid]::NewGuid().ToString('N'))
$block = New-Object byte[] ($BlockKB * 1KB)
(New-Object Random).NextBytes($block)
$blocks = [math]::Ceiling($SizeMB * 1MB / $block.Length)

$rows = for ($r = 1; $r -le $Runs; $r++) {
    $fs = $null
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $fs = New-Object IO.FileStream($file, 'Create', 'Write', 'None', $block.Length, [IO.FileOptions]::WriteThrough)
        for ($i = 0; $i -lt $blocks; $i++) { $fs.Write($block, 0, $block.Length) }
        $fs.Flush($true); $fs.Dispose(); $sw.Stop()
        $writeSec = $sw.Elapsed.TotalSeconds

        $sw.Restart()
        $fs = New-Object IO.FileStream($file, 'Open', 'Read', 'None', $block.Length, [IO.FileOptions]::SequentialScan)
        while ($fs.Read($block, 0, $block.Length) -gt 0) { }
        $fs.Dispose(); $sw.Stop()
        $readSec = $sw.Elapsed.TotalSeconds

        $mb = $blocks * $block.Length / 1MB
        [pscustomobject]@{
            Run          = $r
            WriteMBps    = [math]::Round($mb / $writeSec, 1)
            ReadMBps     = [math]::Round($mb / $readSec, 1)
            WriteMbitps  = [math]::Round($mb * 8.388608 / $writeSec, 0)
            ReadMbitps   = [math]::Round($mb * 8.388608 / $readSec, 0)
        }
    } finally {
        if ($fs) { $fs.Dispose() }
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}

$rows | Format-Table -AutoSize
[pscustomobject]@{
    Path        = $Path
    SizeMB      = $SizeMB
    BlockKB     = $BlockKB
    AvgWriteMBps = [math]::Round(($rows | Measure-Object WriteMBps -Average).Average, 1)
    AvgReadMBps  = [math]::Round(($rows | Measure-Object ReadMBps -Average).Average, 1)
}
