# Contributing

## Contribution Types

| Type | Process | Review Required |
|------|---------|-----------------|
| Typo/grammar fixes | Pull Request | Maintainer |
| Clarifications (non-semantic) | Pull Request | Maintainer |
| New invariants | RFC | DAO Vote |
| State machine changes | RFC | DAO Vote |
| New capabilities | RFC | DAO Vote |
| Breaking changes | RFC | DAO Vote |

## Pull Request Process

1. Fork the repository
2. Create a branch from `develop`
3. Make changes
4. Submit Pull Request to `develop`
5. Address review feedback
6. Maintainer merges upon approval

### Branch Naming

```
docs/fix-typo-presence
docs/clarify-epoch-bounds
```

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
docs: fix typo in presence.md
docs(epochs): clarify active state duration
refactor(invariants): consolidate INV1-13 descriptions
```

## RFC Process

Protocol modifications require an RFC. See [rfcs/README.md](rfcs/README.md).

### When RFC is Required

- Adding or modifying invariants (INV1-42+)
- Changing state transitions
- Adding new epoch capabilities
- Adding new message types
- Any breaking change

### RFC Submission

1. Copy `rfcs/0000-template.md` to `rfcs/NNNN-title.md`
2. Complete all sections
3. Submit Pull Request
4. Minimum 7-day review period
5. DAO vote for approval
6. Implementation upon acceptance

## Code of Conduct

- Be respectful and constructive
- Focus on technical merit
- Provide clear rationale for changes
- Respond to feedback promptly

## Questions

Open an issue for questions about the specification or contribution process.
