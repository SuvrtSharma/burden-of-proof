# Create the local cluster once. Listens on localhost only, with trust auth
# for local connections and no password (dev only, ADR-0015). Uses the
# builtin C.UTF-8 collation, so ORDER BY is byte-wise and the same on every
# machine, which our ordering claims depend on.
. (Join-Path $PSScriptRoot '_env.ps1')

if (Test-Path (Join-Path $PgData 'PG_VERSION')) {
    Write-Host "Cluster already exists at $PgData"
    exit 0
}

New-Item -ItemType Directory -Force $PgData | Out-Null
& (Join-Path $PgBin 'initdb.exe') -D $PgData -U postgres -A trust -E UTF8 `
    --locale=C --locale-provider=builtin --builtin-locale=C.UTF-8 `
    -c listen_addresses=localhost -c port=$PgPort
exit $LASTEXITCODE
