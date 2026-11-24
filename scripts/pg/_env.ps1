# Shared settings for the local, portable Postgres (ADR-0015).
# Override any of these with environment variables before calling a script.

$PgBin  = if ($env:BURDEN_OF_PROOF_PG_BIN)  { $env:BURDEN_OF_PROOF_PG_BIN }  else { Join-Path $env:LOCALAPPDATA 'Programs\pgsql-18.6\bin' }
$PgPort = if ($env:BURDEN_OF_PROOF_PG_PORT) { $env:BURDEN_OF_PROOF_PG_PORT } else { '5432' }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PgData   = Join-Path $RepoRoot '.local\pg18\data'
$PgLog    = Join-Path $RepoRoot '.local\pg18\server.log'

if (-not (Test-Path (Join-Path $PgBin 'pg_ctl.exe'))) {
    throw "Postgres binaries not found in '$PgBin'. Set BURDEN_OF_PROOF_PG_BIN or see ADR-0015."
}
