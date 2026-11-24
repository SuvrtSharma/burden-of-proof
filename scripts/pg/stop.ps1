# Stop the local cluster (fast mode: roll back open transactions, then exit).
. (Join-Path $PSScriptRoot '_env.ps1')

& (Join-Path $PgBin 'pg_ctl.exe') -D $PgData -m fast -w stop
exit $LASTEXITCODE
