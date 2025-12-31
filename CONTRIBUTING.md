# Contributing to WP Code Check

Thank you for your interest in contributing to **WP Code Check**! We welcome contributions from the WordPress community.

---

## 🚀 How to Contribute

### Reporting Bugs

1. **Search existing issues** to avoid duplicates
2. **Create a new issue** with:
   - Clear title describing the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Your environment (OS, bash version, WordPress version)
   - Sample code that triggers the issue (if applicable)

### Suggesting Features

1. **Check existing feature requests** to avoid duplicates
2. **Create a new issue** with:
   - Clear description of the feature
   - Use case / problem it solves
   - Example usage (if applicable)

### Submitting Pull Requests

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/my-new-check`)
3. **Make your changes**
4. **Add tests** (see `dist/tests/fixtures/` for examples)
5. **Run the test suite** (`dist/tests/run-fixture-tests.sh`)
6. **Update documentation** (README.md, CHANGELOG.md)
7. **Commit with clear messages** (see commit guidelines below)
8. **Push to your fork** and submit a pull request

---

## 📝 Development Guidelines

### Adding New Performance Checks

All checks should follow this pattern:

```bash
# In dist/bin/check-performance.sh

run_check "ERROR|WARNING" "CRITICAL|HIGH|MEDIUM|LOW" \
  "Check name" "rule-id" \
  "-E pattern1" \
  "-E pattern2"
```

**Example:**
```bash
run_check "ERROR" "CRITICAL" \
  "Unbounded posts_per_page" "unbounded-posts-per-page" \
  "-E posts_per_page[[:space:]]*=>[[:space:]]*-1"
```

### Test Fixtures

Every new check **must** have test fixtures:

1. **Add antipattern** to `dist/tests/fixtures/antipatterns.php`
2. **Add safe pattern** to `dist/tests/fixtures/clean-code.php`
3. **Update expected counts** in `dist/tests/run-fixture-tests.sh`

### Code Style

- **Bash**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- **Comments**: Explain *why*, not *what*
- **Functions**: One responsibility per function
- **Variables**: Use descriptive names (`FINDING_COUNT` not `fc`)

---

## 🧪 Testing

### Run All Tests

```bash
cd dist/tests
./run-fixture-tests.sh
```

### Test Individual Checks

```bash
cd dist/bin
./check-performance.sh --paths ../tests/fixtures/antipatterns.php
```

Expected output:
- **Errors**: 6+ (depending on active checks)
- **Warnings**: 4+

---

## 📋 Commit Message Guidelines

Use conventional commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Adding/updating tests
- `refactor`: Code restructuring (no behavior change)
- `perf`: Performance improvement
- `chore`: Maintenance tasks

**Examples:**
```
feat(checks): add detection for unbounded get_users()

Detects get_users() calls without 'number' parameter which can
fetch ALL users and crash sites with large user bases.

Closes #42
```

```
fix(html): display full path instead of "." in report header

When scanning with --paths ., the HTML report now shows the
resolved absolute path instead of just a dot.
```

---

## 🔒 Security

**Do NOT commit:**
- API keys, tokens, or credentials
- User-generated logs or reports
- Proprietary plugin/theme code
- Personal information

If you discover a security vulnerability, please email **security@hypercart.com** instead of opening a public issue.

---

## 📄 License

By contributing, you agree that your contributions will be licensed under the **Apache License 2.0**, the same license as the project.

See [LICENSE](LICENSE) for full terms.

---

## 🙏 Recognition

Contributors will be recognized in:
- GitHub contributors page
- CHANGELOG.md (for significant contributions)
- Project README (for major features)

---

## ❓ Questions?

- **Documentation**: See [README.md](README.md) and [dist/README.md](dist/README.md)
- **Issues**: [GitHub Issues](https://github.com/YOUR_ORG/wp-code-check/issues)
- **Email**: support@hypercart.com

---

**Thank you for helping make WordPress faster and more secure!** 🚀

