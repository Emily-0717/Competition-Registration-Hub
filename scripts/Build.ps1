param([string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio')
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$env:JAVA_HOME = Join-Path $DevEco 'jbr'
$env:DEVECO_SDK_HOME = Join-Path $DevEco 'sdk'
$nodePath = Join-Path $DevEco 'tools\node\node.exe'
$hvigorPath = Join-Path $DevEco 'tools\hvigor\bin\hvigorw.js'
Push-Location $projectPath
try {
  & $nodePath $hvigorPath --mode module -p product=default -p module=entry@default assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) { throw '构建失败，请检查 DevEco Studio 工程同步和 SDK 安装。' }
} finally { Pop-Location }
