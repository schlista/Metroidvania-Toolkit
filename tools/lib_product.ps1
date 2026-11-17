# Read top-level product scalars without executing Lua. Keep this strict format
# contract in sync with tools/product_identity.py and mvtk/core/product.lua.
function Get-ToolkitProduct {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    $path = Join-Path $Root 'mvtk/core/product.lua'
    $required = [ordered]@{
        id = [string]
        name = [string]
        placeholder_title = [string]
        zip_prefix = [string]
        tag_prefix = [string]
        license_header = [string]
        repository_url = [string]
        v1_cut_gate = [bool]
        property_type_id_floor = [long]
    }
    function Fail-Product([int]$Line, [string]$Message) {
        throw ('{0}:{1}: {2}' -f $path, $Line, $Message)
    }
    try { $lines = [IO.File]::ReadAllLines($path, [Text.UTF8Encoding]::new($false, $true)) }
    catch { Fail-Product 1 "cannot read product data: $_" }
    $values = [Collections.Hashtable]::new([StringComparer]::Ordinal)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $opened = $false
    $closed = $false
    $depth = 0
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $number = $i + 1
        $line = $lines[$i].Trim()
        if ($depth -gt 0) {
            # Ignore braces inside short strings and line comments.
            $code = [regex]::Replace($line, '"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|--.*', '')
            foreach ($char in $code.ToCharArray()) {
                if ($char -ceq '{') { $depth++ }
                elseif ($char -ceq '}') {
                    $depth--
                    if ($depth -eq 0) {
                        if ($line -cne '},') { Fail-Product $number 'nested table must close on its own line with },' }
                        break
                    }
                }
            }
            continue
        }
        if ($line -eq '' -or $line.StartsWith('--')) { continue }
        if ($closed) { Fail-Product $number 'unexpected text after returned table' }
        if (-not $opened) {
            if ($line -cne 'return {') { Fail-Product $number 'expected return { on its own line' }
            $opened = $true
            continue
        }
        if ($line -ceq '}') { $closed = $true; continue }
        $scalar = [regex]::Match($line, '^([a-z][a-z0-9_]*)\s*=\s*("[^"\\]*"|true|false|[0-9]+),$')
        $block = [regex]::Match($line, '^([a-z][a-z0-9_]*)\s*=\s*\{$')
        if (-not $scalar.Success -and -not $block.Success) { Fail-Product $number 'malformed top-level entry' }
        $key = if ($scalar.Success) { $scalar.Groups[1].Value } else { $block.Groups[1].Value }
        if (-not $seen.Add($key)) { Fail-Product $number "duplicate key $key" }
        if ($block.Success) {
            if ($required.Contains($key)) { Fail-Product $number "$key must be a scalar" }
            $depth = 1
            continue
        }
        $token = $scalar.Groups[2].Value
        if ($token.StartsWith('"')) { $value = $token.Substring(1, $token.Length - 2) }
        elseif ($token -ceq 'true' -or $token -ceq 'false') { $value = $token -ceq 'true' }
        else {
            $value = 0L
            if (-not [long]::TryParse($token, [ref]$value) -or $value -gt 9007199254740991) {
                Fail-Product $number "integer exceeds Lua's exact integer range"
            }
        }
        if ($required.Contains($key) -and $value.GetType() -ne $required[$key]) {
            Fail-Product $number "wrong scalar type for $key"
        }
        $values[$key] = $value
    }
    $end = [Math]::Max(1, $lines.Length)
    if ($depth -gt 0) { Fail-Product $end 'unterminated nested table' }
    if (-not $closed) { Fail-Product $end 'missing returned table closing brace' }
    foreach ($key in $required.Keys) {
        if (-not $values.ContainsKey($key)) { Fail-Product $end "missing required key $key" }
    }
    return $values
}
