#kubectl use context or kuc

param (
  [switch]$h,
  [switch]$c
)


function GetInput {
  $config_dir="$env:USERPROFILE\.kube\config.d"

  if (-not (Test-Path -Path "$config_dir" -PathType Container)) {
    Write-Host "`"$config_dir`" doesn't exist yet. Please create it"
    Exit 1
  }

  $contexts=Get-ChildItem $config_dir | Sort-Object LastWriteTime | Select-Object -ExpandProperty Name 

  Write-Host "No config selected or is invalid, going into interactive mode..."
 
  While ($true){
    Write-Host "Choose a context to use..."
    for ($i = 0; $i -lt $contexts.Count; $i++) {
      Write-Host "#$($i+1)-> $($contexts[$i])"
    }
    $option=Read-Host "#? "
    $option=$($option - 1)
    if ( $option -lt $contexts.Count ){
	Write-Host "Using context $($contexts[$option])..."
      $env:KUBECONFIG="$config_dir\$($contexts[$option])"
      break
    }
    else {
      Write-Host "Invalid input. Please enter numbers between 1 and $contexts.Count..."
    }
  }
}

if ($h) {
  Write-Host "kuc for powershell"
  Write-Host "-h -> show this page"
  Write-Host "-c -> show current config being used"
  Exit
}

if ($c) {
   Write-Host "Current kubectl context is $env:KUBECONFIG"
   Exit
}

GetInput
