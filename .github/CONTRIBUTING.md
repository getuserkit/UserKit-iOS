# Contributing to UserKit

Thanks for your interest in contributing to UserKit! We welcome contributions from the community.

## Pull Requests

1. Fork the repository and create your branch from `main`
2. Add tests for any new code you write
3. Ensure all tests pass before submitting
4. Update documentation if you're changing public APIs
5. Submit your pull request!

All pull requests will be reviewed by maintainers. Please be patient and responsive to feedback.

## Testing

All new code must include tests.

### Running Tests Locally

```bash
xcodebuild test \
  -scheme UserKit \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Or press **Cmd + U** in Xcode.

Tests automatically run via GitHub Actions on every push and pull request.

## Issues

Found a bug or have a feature request? Please open an issue! When reporting bugs, include:

- iOS version
- Xcode version
- Steps to reproduce
- Expected vs actual behavior
- Sample code if applicable

## License

By contributing to UserKit, you agree that your contributions will be licensed under the MIT License.
