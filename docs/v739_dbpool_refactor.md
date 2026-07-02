# DBPool Interface Refactor — Design Note (v739+)

## Background

The v733–v735 fix stack added a `plan_type` PATCH branch to
`admin.Handler#updateCredential`. The branch's unit-test coverage
was limited to validation paths (reject-invalid, allow-list) because
`Handler.db` was a concrete `*pgxpool.Pool` and pgxmock's
`PgxPoolIface` could not satisfy it. The v737 audit identified this
as gap M1 ("MEDIUM: pgxmock refactor blocked by Handler.db being
concrete *pgxpool.Pool").

## v738 attempt (rolled back)

The v738 cycle attempted to refactor `Handler.db` from `*pgxpool.Pool`
to an interface `DBPool` defined in a new package
`internal/dbpool`. The interface covered the four methods actually
called: `Query`, `QueryRow`, `Exec`, `Begin`.

**What worked**:
- The interface definition is straightforward (4 methods).
- 6 cross-package helpers (`settings.WriteAudit`, `settings.ListAudit`,
  `modelcatalog.UpsertCredentialModel`, `modelcatalog.ClearProviderBindings`,
  `maas.NewService`, `bg.PickProbeModelForCredential`) successfully
  accepted the interface.
- pgxmock-based happy-path tests were demonstrated to work for the
  plan_type PATCH branch (read prev plan_type, BEGIN, UPDATE creds,
  UPDATE cmb, COMMIT, read new plan_type, INSERT settings_audit).

**What broke the rollout**:

1. **Explosion radius**. The refactor required touching 23 admin files
   plus 4 cross-package files. Most of the touching was mechanical
   field/parameter renames (`db *pgxpool.Pool` → `db DBPool`), but
   some sites had *white-space-padded* `db     *pgxpool.Pool` or
   *named-in-constructor* `Handler{db: pool}` patterns. The sed
   pattern needed multiple passes with hand-rolled perl lookbehind,
   and macOS BSD perl's incomplete regex support meant some passes
   silently failed.

2. **Test literal fragility**. With `*pgxpool.Pool` the test
   `&Handler{db: nil}` works because `nil` satisfies any interface.
   After the refactor, `nil` still satisfies the interface — but
   `&Handler{db: somePool}` where `somePool *pgxpool.Pool` works
   ONLY if `*pgxpool.Pool` satisfies the interface. It does, but
   only because we kept the same package-local type alias.

3. **Test satisfaction mismatch**. `pgxmock.PgxPoolIface` does
   satisfy our `DBPool` interface (it implements all 4 methods).
   But the test file needs `&Handler{db: mock.(DBPool)}` to convert
   the mock interface to the package-local alias. The cast is
   mechanical but easy to forget.

4. **Build agent linter interference**. Multiple `linter` rewrites
   between the original sed and the final build pass ate some
   intermediate state. A multi-PR-style refactor across this many
   files is sensitive to such interference.

The v738 cycle ended with a clean git revert of admin/ and
internal/dbpool/ after I observed the breakage; this design note
captures the trade-offs.

## v739+ recommended approach

Rather than a single sweeping refactor, v739+ should adopt a
**staged rollout** with each step producing a working build:

### Stage 1: introduce `internal/dbpool` (no callers)

Land a PR that adds `internal/dbpool/dbpool.go` with the interface
definition and full package documentation. **No callers change.**
This is a no-op for runtime behaviour and produces a foundation
for the staged refactor.

### Stage 2: introduce a package-local alias in `admin/`

In a second PR, add `admin/dbpool.go` with `type DBPool =
dbpool.DBPool` and document the staged refactor in progress.
**No callers change.** This is a no-op for runtime behaviour and
gives admin/ a forward-compatible name for the interface.

### Stage 3: refactor a single function with a long history

Pick **one** admin handler that has both:
- a strong test-coverage story (so we can detect regressions)
- a clear interface boundary (so the refactor is contained)

Suggested target: `admin/handler.go#admin` (the JWT-auth wrapper).
Replace its `*pgxpool.Pool` parameter with `DBPool`. Verify all
builds and tests pass. **Do not refactor `Handler.db` yet.**

### Stage 4: refactor the cross-package helpers

In separate, smaller PRs:
- `settings.WriteAudit` / `settings.ListAudit` (one PR)
- `modelcatalog.UpsertCredentialModel` / `modelcatalog.ClearProviderBindings` (one PR)
- `maas.NewService` (one PR)
- `bg.PickProbeModelForCredential` (one PR)

Each PR keeps `*pgxpool.Pool` parameter + adds `DBPool` parameter
side-by-side. Internal callers continue to pass the concrete pool;
external callers (and the new tests) pass the interface. Once all
six helpers take `DBPool`, the next stage is mechanical.

### Stage 5: refactor `Handler.db`

After all six helpers take `DBPool`, change `admin.Handler.db` from
`*pgxpool.Pool` to `DBPool`. The admin package's own helpers
(50+ functions, see the audit output) will all need
`db *pgxpool.Pool` → `db DBPool`. This is the largest single change
in the rollout.

**Tooling recommendation for stage 5**:

```bash
# Run from /Users/xutaohuang/workspace/llm-gateway-go-2

# 1. Field declarations: '<spaces>*pgxpool.Pool' on its own line
#    (typically struct fields; preserve indentation)
perl -i -pe 's/^(\s+)(\*pgxpool\.Pool)\b/$1DBPool/g' admin/*.go

# 2. Function parameters: '(<ident><spaces>*pgxpool.Pool' in declarations
perl -i -pe 's/(\s)(\*pgxpool\.Pool)([,\)])/$1DBPool$3/g' admin/*.go

# 3. Field-name restore: after the previous sed, lines that lost
#    their field name (e.g., `<spaces>DBPool` with no preceding
#    identifier) need the field name prepended.
#    Use a lookbehind tool that handles negative lookbehind
#    reliably (Go's regexp package or python, NOT BSD perl).
python3 -c "
import re, sys
for path in sys.argv[1:]:
    with open(path) as f: src = f.read()
    # Match: word-boundary DBPool NOT preceded by an identifier character
    new = re.sub(r'(?<![a-zA-Z0-9_.])DBPool\b', 'db DBPool', src)
    with open(path, 'w') as f: f.write(new)
" admin/*.go
```

The v738 cycle used BSD perl which lacks `\K` and lookbehind
support, so step 3 silently failed in places. Use Python or `gofmt -r`
for the round.

### Stage 6: tests

Only after stages 1–5 are merged. Replace the docstring marker
test in `admin/provider_credential_plan_type_test.go` with real
pgxmock tests as designed in v738.

## Risk register

- **Performance**: zero impact. Interface dispatch on a single-method
  call is inlined by the Go compiler.
- **API breakage**: zero. The new `DBPool` interface is a strict
  subset of `*pgxpool.Pool`'s method set, so any code that compiled
  with the concrete type continues to compile with the interface.
- **Test failures**: medium. The v738 cycle saw `pgxmock.PgxPoolIface`
  sometimes failing to type-assert to `DBPool` cleanly in
  `_test.go` files. The fix is explicit type assertion
  (`mock.(DBPool)`) at the assignment site.
- **Linter/build-agent interference**: high (observed in v738). A
  multi-file refactor of this size benefits from a single
  focused session, not interrupted agentic loops.

## Closing

The refactor IS the right thing to do — the v738 cycle successfully
demonstrated that DBPool is sufficient, pgxmock is workable, and
the cross-package helpers all accept the interface. The
recommendation is to break it into staged PRs (6 PRs minimum)
rather than a single sweeping change, with each PR landing a
working build and test suite. The v738 cycle spent roughly
the same wall-clock time trying to do all six stages in one
sitting and ended with a revert.

## Plan_type test status (current — pre-refactor)

`admin/provider_credential_plan_type_test.go` has 6 test
functions, all passing:

1. `TestUpdateCredentialBody_ParsesPlanType` — body decode
2. `TestUpdateCredentialBody_AcceptsNullPlanType` — empty string
3. `TestUpdateCredentialHandler_RejectsInvalidPlanType` — invalid allow-list
4. `TestUpdateCredentialHandler_AbsentPlanType` — no PATCH field
5. `TestPlanType_AllowList` — 5 deny subtests + 10 allow subtests
6. `TestUpdateCredentialHandler_HappyPathPlanType` — docstring marker
   for the v738 pgxmock refactor; the implementation was
   demonstrated to work in the v738 cycle but not merged.

Real pgxmock happy-path coverage of plan_type PATCH is **NOT yet**
landed. The docstring marker test (6) is the v738 placeholder.
