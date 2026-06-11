
$ErrorActionPreference = 'Stop'

function Get-AppJsxPath {
  $candidates = @(
    (Join-Path (Get-Location) 'frontend/src/App.jsx'),
    (Join-Path (Get-Location) 'src/App.jsx'),
    (Join-Path $PSScriptRoot 'frontend/src/App.jsx'),
    (Join-Path $PSScriptRoot 'src/App.jsx')
  )
  foreach ($p in $candidates) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

function Replace-Exact {
  param(
    [string]$Text,
    [string]$Search,
    [string]$Replacement,
    [string]$Label,
    [bool]$Required = $true
  )
  if ($Text.Contains($Search)) {
    return $Text.Replace($Search, $Replacement)
  }
  if ($Required) { throw "Blocco non trovato: $Label" }
  return $Text
}

function Replace-Regex {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Replacement,
    [string]$Label,
    [bool]$Required = $true
  )
  $opt = [System.Text.RegularExpressions.RegexOptions]::Singleline
  if ([regex]::IsMatch($Text, $Pattern, $opt)) {
    return [regex]::Replace($Text, $Pattern, $Replacement, $opt)
  }
  if ($Required) { throw "Blocco non trovato: $Label" }
  return $Text
}

$app = Get-AppJsxPath
if (-not $app) { throw 'App.jsx non trovato' }
Write-Host "✅ Trovato App.jsx in: $app"

$backup = $app -replace 'App\.jsx$', 'App_backup_fix_targa_auto.jsx'
if (-not (Test-Path $backup)) {
  Copy-Item $app $backup
  Write-Host "✅ Backup creato: $backup"
} else {
  Write-Host "ℹ️ Backup già presente: $backup"
}

$content = Get-Content -LiteralPath $app -Raw -Encoding UTF8
$original = $content

# 1) Campo plate in appointments
if ($content -notmatch 'key:\s*"plate"') {
  $pattern = 'appointments:\s*\{\s*label:\s*"Appuntamenti",\s*fields:\s*\[\s*\{ key: "customer_id", label: "Cliente", type: "select", source: "customers", optionLabel: "name", required: true \},\s*'
  $replacement = "$0`r`n      { key: `"plate`", label: `"Targa`", type: `"text`" },"
  $content = Replace-Regex $content $pattern $replacement 'campo plate appointments'
}

# 2) Helper findVehicleByPlate
if ($content -notmatch 'function findVehicleByPlate\(') {
  $content = Replace-Regex $content 'function parseServiceIds\(value\) \{.*?\n\}' "$0`r`n`r`nfunction findVehicleByPlate(vehicles, plate) {`r`n  const wanted = upperCaseValue(plate);`r`n  if (!wanted) return null;`r`n  return (vehicles || []).find((v) => upperCaseValue(v.targa) === wanted) || null;`r`n}" 'helper targa'
}

# 3) normalizePayload skip plate
if ($content -notmatch 'field\.key === "plate"') {
  $content = Replace-Regex $content '\n\s*payload\[field\.key\] = value;\n' "`n    if (field.key === `"plate`") return;`n    payload[field.key] = value;`n" 'skip plate payload'
}

# 4) updateFormValue completo
$updateFormValueNew = @'
function updateFormValue(entityKey, fieldKey, value) {
    setForms((prev) => {
      const nextEntity = {
        ...prev[entityKey],
        [fieldKey]: value
      };

      if (entityKey === "appointments" && fieldKey === "customer_id") {
        nextEntity.vehicle_id = "";
        nextEntity.plate = "";
      }

      if (entityKey === "appointments" && fieldKey === "vehicle_id") {
        const vehicle = refs.vehiclesById[value];
        if (vehicle) {
          nextEntity.plate = upperCaseValue(vehicle.targa);
          nextEntity.customer_id = String(vehicle.customer_id ?? nextEntity.customer_id ?? "");
        }
      }

      if (entityKey === "appointments" && fieldKey === "plate") {
        const plate = upperCaseValue(value);
        nextEntity.plate = plate;
        const vehicle = findVehicleByPlate(db.vehicles, plate);
        if (vehicle) {
          nextEntity.vehicle_id = String(vehicle.id);
          nextEntity.customer_id = String(vehicle.customer_id ?? nextEntity.customer_id ?? "");
        } else {
          nextEntity.vehicle_id = "";
        }
      }

      return {
        ...prev,
        [entityKey]: nextEntity
      };
    });
  }
'@
$content = Replace-Regex $content 'function updateFormValue\(entityKey, fieldKey, value\) \{.*?\n  \}' $updateFormValueNew 'updateFormValue'

# 5) updateEditValue completo
$updateEditValueNew = @'
function updateEditValue(entityKey, rowId, fieldKey, value) {
    setEditingRows((prev) => {
      const currentRow = prev[entityKey][rowId] || {};
      const nextRow = {
        ...currentRow,
        [fieldKey]: value
      };

      if (entityKey === "appointments" && fieldKey === "customer_id") {
        nextRow.vehicle_id = "";
        nextRow.plate = "";
      }

      if (entityKey === "appointments" && fieldKey === "vehicle_id") {
        const vehicle = refs.vehiclesById[value];
        if (vehicle) {
          nextRow.plate = upperCaseValue(vehicle.targa);
          nextRow.customer_id = String(vehicle.customer_id ?? nextRow.customer_id ?? "");
        }
      }

      if (entityKey === "appointments" && fieldKey === "plate") {
        const plate = upperCaseValue(value);
        nextRow.plate = plate;
        const vehicle = findVehicleByPlate(db.vehicles, plate);
        if (vehicle) {
          nextRow.vehicle_id = String(vehicle.id);
          nextRow.customer_id = String(vehicle.customer_id ?? nextRow.customer_id ?? "");
        } else {
          nextRow.vehicle_id = "";
        }
      }

      return {
        ...prev,
        [entityKey]: {
          ...prev[entityKey],
          [rowId]: nextRow
        }
      };
    });
  }
'@
$content = Replace-Regex $content 'function updateEditValue\(entityKey, rowId, fieldKey, value\) \{.*?\n  \}' $updateEditValueNew 'updateEditValue'

# 6) startEdit normalized
$content = Replace-Exact $content '    const normalized = { ...row };' "    const normalized = {`r`n      ...row,`r`n      plate: entityKey === `"appointments`" ? (upperCaseValue(refs.vehiclesById[row.vehicle_id]?.targa) || `"`") : row.plate`r`n    };" 'startEdit plate' $false

# 7) createEntity sourceForm
$content = Replace-Exact $content '      const payload = normalizePayload(config, currentForm);' @'
      let sourceForm = { ...currentForm };
      if (entityKey === "appointments" && sourceForm.plate) {
        const vehicle = findVehicleByPlate(db.vehicles, sourceForm.plate);
        if (vehicle) {
          sourceForm.vehicle_id = String(vehicle.id);
          sourceForm.customer_id = String(vehicle.customer_id ?? sourceForm.customer_id ?? "");
        }
      }

      const payload = normalizePayload(config, sourceForm);
'@ 'createEntity sourceForm' $false

# 8) saveEntity sourceRow
$content = Replace-Exact $content '      const payload = normalizePayload(config, editable);' @'
      let sourceRow = { ...editable };
      if (entityKey === "appointments" && sourceRow.plate) {
        const vehicle = findVehicleByPlate(db.vehicles, sourceRow.plate);
        if (vehicle) {
          sourceRow.vehicle_id = String(vehicle.id);
          sourceRow.customer_id = String(vehicle.customer_id ?? sourceRow.customer_id ?? "");
        }
      }

      const payload = normalizePayload(config, sourceRow);
'@ 'saveEntity sourceRow' $false

# 9) formatDisplayValue plate
if ($content -notmatch 'field\.key === "plate"') {
  $content = Replace-Regex $content 'if \(field\.key === "customer_id"\) return refs\.customersById\[value\]\?\.name \|\| "-";\s*if \(field\.key === "vehicle_id"\) return refs\.vehiclesById\[value\]\?\.targa \|\| "-";' "if (field.key === `"customer_id`") return refs.customersById[value]?.name || `"-`";`r`n    if (field.key === `"vehicle_id`") return refs.vehiclesById[value]?.targa || `"-`";`r`n    if (field.key === `"plate`") return upperCaseValue(value) || `"-`";" 'format plate' $false
}

# 10) renderFieldInput completo
$renderFieldInputNew = @'
function renderFieldInput(entityKey, field, values, onChange, scope = "base") {
    const rawValue = values[field.key] ?? (field.type === "checkbox" ? false : "");
    const labelNode = (
      <label style={fieldLabelStyle}>
        {field.label}
        {field.required ? " *" : ""}
      </label>
    );
    const wrapField = (node) => (
      <div style={fieldGroupStyle}>
        {labelNode}
        {node}
      </div>
    );
    if (
      field.key === "rental_company" &&
      entityKey === "vehicles" &&
      normalizeTextValue("vehicle_type", values?.vehicle_type) !== "Noleggio"
    ) {
      return wrapField(
        <div style={fieldMutedStyle}>Compila solo se il veicolo è a noleggio</div>
      );
    }
    if (field.type === "select") {
      let options = db[field.source] || [];
      if (entityKey === "appointments" && field.key === "vehicle_id") {
        const selectedCustomerId = values?.customer_id ? String(values.customer_id) : "";
        if (selectedCustomerId) {
          options = options.filter((opt) => String(opt.customer_id ?? "") === selectedCustomerId);
        }
      }
      return wrapField(
        <select
          value={rawValue ?? ""}
          onChange={(e) => onChange(field.key, e.target.value)}
          style={inputStyle}
        >
          <option value="">Seleziona {field.label}</option>
          {options.map((opt) => {
            let optionText = opt[field.optionLabel] || `#${opt.id}`;
            if (field.source === "workOrders") {
              optionText = `#${opt.id} - ${opt.description || ""}`;
            }
            if (field.source === "tires") {
              optionText = `${normalizeTextValue("brand", opt.brand)} ${normalizeTextValue("model", opt.model)} ${normalizeTextValue("size", opt.size)}`.trim();
            }
            if (field.source === "vehicles") {
              optionText = upperCaseValue(opt.targa);
            }
            return (
              <option key={opt.id} value={opt.id}>
                {optionText}
              </option>
            );
          })}
        </select>
      );
    }
    if (field.type === "static-select") {
      return wrapField(
        <select
          value={rawValue ?? ""}
          onChange={(e) => onChange(field.key, normalizeTextValue(field.key, e.target.value))}
          style={inputStyle}
        >
          <option value="">Seleziona {field.label}</option>
          {(field.options || []).map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      );
    }
    if (field.type === "service-checklist") {
      return wrapField(
        <ServiceChecklist
          services={db.services || []}
          value={rawValue}
          onChange={(nextValue) => onChange(field.key, nextValue)}
        />
      );
    }
    if (field.type === "checkbox") {
      return wrapField(
        <label style={checkboxWrapStyle}>
          <input
            type="checkbox"
            checked={!!rawValue}
            onChange={(e) => onChange(field.key, e.target.checked)}
          />
          <span>{rawValue ? "SI" : "NO"}</span>
        </label>
      );
    }
    const inputValue = field.type === "datetime-local" ? formatDateForInput(rawValue) : rawValue;
    if (entityKey === "appointments" && field.key === "plate") {
      const plateSuggestions = (db.vehicles || []).map((v) => upperCaseValue(v.targa)).filter(Boolean).sort();
      const listId = getSuggestionListId(entityKey, field.key, scope);
      const matchedVehicle = findVehicleByPlate(db.vehicles, inputValue);
      const matchedCustomer = matchedVehicle?.customer_id ? refs.customersById[matchedVehicle.customer_id] : null;
      return wrapField(
        <>
          <input
            type="text"
            list={plateSuggestions.length ? listId : undefined}
            value={upperCaseValue(inputValue)}
            placeholder="Inserisci targa"
            onChange={(e) => onChange(field.key, upperCaseValue(e.target.value))}
            style={inputStyle}
          />
          {plateSuggestions.length > 0 && (
            <datalist id={listId}>
              {plateSuggestions.map((item) => (
                <option key={item} value={item} />
              ))}
            </datalist>
          )}
          {matchedVehicle ? (
            <div style={appointmentVehicleInfoStyle}>
              <div><strong>Cliente:</strong> {normalizeTextValue("name", matchedCustomer?.name) || "-"}</div>
              <div><strong>Targa:</strong> {upperCaseValue(matchedVehicle.targa) || "-"}</div>
              <div><strong>Marca:</strong> {normalizeTextValue("marca", matchedVehicle.marca) || "-"}</div>
              <div><strong>Modello:</strong> {normalizeTextValue("modello", matchedVehicle.modello) || "-"}</div>
            </div>
          ) : upperCaseValue(inputValue) ? (
            <div style={fieldMutedStyle}>Targa non trovata nel database veicoli.</div>
          ) : null}
        </>
      );
    }
    if (field.type === "text") {
      const suggestions = getSuggestions(entityKey, field, values);
      const listId = getSuggestionListId(entityKey, field.key, scope);
      return wrapField(
        <>
          <input
            type="text"
            list={suggestions.length ? listId : undefined}
            value={inputValue}
            placeholder=""
            onChange={(e) => onChange(field.key, e.target.value)}
            onBlur={(e) => onChange(field.key, normalizeTextValue(field.key, e.target.value))}
            style={inputStyle}
          />
          {suggestions.length > 0 && (
            <datalist id={listId}>
              {suggestions.map((item) => (
                <option key={item} value={item} />
              ))}
            </datalist>
          )}
        </>
      );
    }
    return wrapField(
      <input
        type={field.type === "datetime-local" ? "datetime-local" : field.type === "number" ? "number" : "text"}
        value={inputValue}
        placeholder=""
        onChange={(e) => onChange(field.key, coerceInputValue(field, e.target.value))}
        style={inputStyle}
      />
    );
  }
'@
$content = Replace-Regex $content 'function renderFieldInput\\(entityKey, field, values, onChange, scope = \"base\"\\) \\{.*?\\n  \\}' $renderFieldInputNew 'renderFieldInput completo'

# 11) style info vehicle
if ($content -notmatch 'const appointmentVehicleInfoStyle = \{') {
  $content = Replace-Regex $content 'const fieldMutedStyle = \{.*?\n\};' "$0`r`n`r`nconst appointmentVehicleInfoStyle = {`r`n  marginTop: 8,`r`n  padding: 10,`r`n  borderRadius: 8,`r`n  border: `"1px solid #2D3B4A`",`r`n  background: `"#0B0F13`",`r`n  color: `"#C7D2DE`",`r`n  fontSize: 13,`r`n  display: `"flex`",`r`n  flexDirection: `"column`",`r`n  gap: 4`r`n};" 'style info vehicle'
}

Set-Content -LiteralPath $app -Value $content -Encoding UTF8
Writest "👉 Ora esegui: npm run dev"
