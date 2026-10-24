# cloc-patterns.sh: what the cloc wrapper skips and how it classifies files.
# Sourced by bin/cloc; not meant to run on its own.
# shellcheck disable=SC2034  # every name here is read by bin/cloc

# Report sections, in print order. Docs and data are told apart by language,
# code and tests by path (TEST_FILES below).
CATEGORY_CODE=1
CATEGORY_TESTS=2
CATEGORY_DOCS=3
CATEGORY_DATA=4
CATEGORY_LABELS='Code|Tests|Docs|Config & data'
DOC_LANGS='Markdown|reStructuredText|AsciiDoc|Org Mode|Text|TeX'
# Display names that replace cloc's own, as cloc=shown pairs.
LANG_RENAMES='Bourne Shell=Bash|Bourne Again Shell=Bash'
DATA_LANGS='JSON|JSON5|YAML|TOML|INI|XML|XSD|DTD|CSV|Properties|SVG'

EXCLUDE_DIRS=(
    .git .svn .hg .idea .direnv .cache
    node_modules bower_components jspm_packages .pnpm-store .yarn
    .next .next-e2e .nuxt .output .svelte-kit .astro .angular .expo .vite
    .turbo .parcel-cache .docusaurus .vercel .netlify .serverless storybook-static
    dist build out coverage .nyc_output playwright-report test-results
    playwright-artifacts playwright-screenshots
    .venv venv __pycache__ .pytest_cache .mypy_cache .ruff_cache .tox .nox
    .eggs site-packages .ipynb_checkpoints htmlcov
    target .gradle .m2 .mvn .kotlin
    vendor
    obj packages
    .bundle .dart_tool .pub-cache Pods DerivedData Carthage
    _build deps .elixir_ls .stack-work dist-newstyle .terraform
    CMakeFiles cmake-build-debug cmake-build-release .ccls-cache .zig-cache zig-out
)

# Matched against the full path (--fullpath), hence the (^|/) anchors.
EXCLUDE_FILES='(^|/)(package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|deno\.lock|Cargo\.lock|poetry\.lock|Pipfile\.lock|uv\.lock|pdm\.lock|composer\.lock|Gemfile\.lock|mix\.lock|pubspec\.lock|Podfile\.lock|go\.sum|gradle\.lockfile|packages\.lock\.json|flake\.lock|next-env\.d\.ts|[^/]*\.generated\.[^/.]+|[^/]*\.(g|freezed|gr|mocks)\.dart|[^/]*\.pb(\.gw)?\.go|[^/]*_pb2(_grpc)?\.pyi?|[^/]*\.[Dd]esigner\.(cs|vb)|[^/]*\.tsbuildinfo|[^/]*\.min\.(js|css)|[^/]*\.map)$'

# Test code: conventional test dirs, Jest/Vitest/Mocha/Playwright/Cypress
# (*.test.*, *.spec.*, *.cy.*, *.e2e.*), pytest (test_*.py, *_test.py,
# conftest.py), Go/Dart/Elixir (*_test.*), RSpec (*_spec.*), JUnit, Kotest,
# NUnit, xUnit, PHPUnit, XCTest (*Test, *Tests, *Spec, *IT), and the config or
# setup files of those runners.
TEST_FILES='(^|/)(__tests__|__mocks__|tests?|specs?|e2e|cypress|androidTest)/|\.(test|spec|cy|e2e)\.[^/.]+$|(^|/)(test_[^/]*\.py|conftest\.py)$|_(test|spec)\.[^/.]+$|(Test|Tests|Spec|IT|TestCase)\.(java|kt|kts|scala|groovy|cs|fs|vb|php|swift|m|mm)$|(^|/)(jest|vitest|playwright|cypress|karma)\.(config|setup)[^/]*$|(^|/)setupTests\.[^/]+$'
