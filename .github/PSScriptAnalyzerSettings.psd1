@{
  IncludeRules = @(
    'PSUseCompatibleSyntax'
  )

  Rules = @{
    PSUseCompatibleSyntax = @{
      Enable = $true
      TargetVersions = @(
        '5.1'
      )
    }
  }
}
