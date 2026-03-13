# Release

## Release workflow

Use the release helper to bump version, refresh `Gemfile.lock`, create commit/tag, and push:

```bash
# explicit version
bin/release --version 0.2.0

# or env-style
VERSION=0.2.0 bin/release

# semantic bump from current version
bin/release --bump patch
```

Useful options:

- `--dry-run` preview all actions without modifying files/git
- `--no-push` create commit/tag locally only
- `--skip-tests` skip `bundle exec ruby bin/prd spec --mode synthetic`
- `--allow-dirty` bypass clean-working-tree guard

After installation, you can run:

```bash
prd examples/basics_spec.rb
```

If `prd` is not found, add your gem bin directory to `PATH`:

```bash
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
```