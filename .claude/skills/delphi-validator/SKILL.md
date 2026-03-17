---
name: delphi-validator
description: Validates all SimpleORM Delphi source files for Delphi 10.2 Tokyo+ compatibility. Checks inline vars, unit scoping, generics E2506, uses completeness, memory safety, .dpr structure, and conditional compilation. Run anytime to "lint" the project.
user-invocable: true
---

# Delphi 10.2+ Compatibility Validator

Validates the SimpleORM codebase against Delphi 10.2 Tokyo+ compatibility rules. Acts as a static analyzer / linter since we cannot compile in this environment.

## What It Checks (7 Categories)

| Code | Category | Severity | Description |
|------|----------|----------|-------------|
| INLINE-VAR | Inline Variables | ERRO | `var`/`const` inside begin/end, `for var` — require 10.3+ |
| SCOPE-AMBIGUITY | Unit Scoping | WARN | Bare `Format(` with SimpleAttributes in uses, missing unit qualifications |
| GENERICS-E2506 | Generics Restrictions | ERRO | Implementation-local symbols used in generic class methods |
| USES-VISIBILITY | Uses Completeness | ERRO | Types used in interface section but unit only in implementation uses |
| MEMORY-SAFETY | Memory Management | WARN | Leaked objects, swallowed exceptions, bare Free in destructors |
| DPR-STRUCTURE | Program File Structure | ERRO | Invalid .dpr structure (unit keyword, interface/implementation sections) |
| CONDITIONAL-COMPAT | Conditional Compilation | ERRO | Unguarded 10.3+/10.4+ features without RTLVERSION check |

## How to Run

When this skill is invoked, dispatch the `delphi-compatibility-checker` subagent:

```
Agent(
  subagent_type = "delphi-compatibility-checker",
  prompt = "Analyze ALL .pas and .dpr files in src/ for Delphi 10.2+ compatibility. Apply all 7 rule categories. Report every finding with file:line, category, and severity. End with a summary.",
  description = "Delphi 10.2+ compatibility check"
)
```

## After Results

1. **Present the report** to the user as-is
2. **If errors found**: Ask the user if they want you to fix them automatically
3. **If fixing**: Apply fixes following the patterns in `.claude/rules/` and the fix guidance in each finding
4. **After fixing**: Re-run the validator to confirm all issues are resolved

## Quick Reference: Common Fixes

### INLINE-VAR Fix
```pascal
// BEFORE (10.3+ only):
begin
  var LName: String := 'value';
  for var I := 0 to 10 do ...

// AFTER (10.2 compatible):
var
  LName: String;
  I: Integer;
begin
  LName := 'value';
  for I := 0 to 10 do ...
```

### SCOPE-AMBIGUITY Fix
```pascal
// BEFORE (ambiguous):
aErrors.Add(Format(sMSG, [aValue]));

// AFTER (explicit):
aErrors.Add(System.SysUtils.Format(sMSG, [aValue]));
```

### GENERICS-E2506 Fix
```pascal
// BEFORE (local function — triggers E2506):
implementation
function LocalHelper(...): ...; // only in implementation
// used by TSimpleXxx<T>.SomeMethod

// AFTER (promote to interface):
interface
function LocalHelper(...): ...;
implementation
function LocalHelper(...): ...; // implementation stays
```

### USES-VISIBILITY Fix
```pascal
// BEFORE:
interface
uses SimpleInterface; // SimpleTypes NOT here
type
  TMyClass = class
    FCallback: TSimpleErrorCallback; // defined in SimpleTypes!
  end;
implementation
uses SimpleTypes; // too late for interface declarations

// AFTER:
interface
uses SimpleInterface, SimpleTypes; // moved here
```
