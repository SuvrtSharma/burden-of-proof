# Start the local cluster and wait until it accepts connections.
. (Join-Path $PSScriptRoot '_env.ps1')

& (Join-Path $PgBin 'pg_ctl.exe') -D $PgData -l $PgLog -w start
exit $LASTEXITCODE
