```markdown
# Terranex Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches the core development patterns and conventions used in the Terranex TypeScript codebase, which is built on the Vite framework. You will learn about file naming, import/export styles, commit message habits, and how to write and run tests using vitest. This guide also provides suggested commands for common workflows.

## Coding Conventions

### File Naming
- Use **camelCase** for all file names.
  - Example: `userProfile.ts`, `dataFetcher.ts`

### Import Style
- Use **relative imports** for modules within the project.
  - Example:
    ```typescript
    import userService from './userService'
    import utils from '../utils'
    ```

### Export Style
- Use **default exports** for modules.
  - Example:
    ```typescript
    // userService.ts
    const userService = { /* ... */ }
    export default userService
    ```

### Commit Patterns
- Commit messages are **freeform** (no enforced structure).
- Commonly use short prefixes or none at all.
- Average commit message length: **~19 characters**.
  - Example:
    ```
    fix login bug
    add user fetch
    update styles
    ```

## Workflows

_No automated workflows detected in this repository._

## Testing Patterns

- **Testing Framework:** vitest
- **Test File Naming:** Use `.test.ts` suffix.
  - Example: `userService.test.ts`
- **Test Example:**
  ```typescript
  import { describe, it, expect } from 'vitest'
  import userService from './userService'

  describe('userService', () => {
    it('fetches user data', async () => {
      const user = await userService.getUser(1)
      expect(user.id).toBe(1)
    })
  })
  ```
- **Running Tests:** Use the vitest CLI.
  - Example:
    ```
    npx vitest
    ```

## Commands
| Command          | Purpose                              |
|------------------|--------------------------------------|
| /run-tests       | Run all vitest tests                 |
| /format-code     | Format code according to conventions |
| /new-module      | Scaffold a new camelCase module      |
| /commit-guide    | Show commit message tips             |
```