---
globs: '["**/*.bicep", "**/logicapp*.json"]'
description: Apply these practices when reviewing or modifying Logic App definitions
alwaysApply: false
---

When working with Logic App bicep files:
- Use positive conditions instead of negative ones for better visual clarity (e.g., "Check_if_needs_update" instead of "Check_if_not_something")
- Document why 404 errors are handled as they might be expected behavior
- Avoid base64 encoding in logs when possible for better readability
- Consider using Compose actions to normalize API responses before parsing
- The rand() function works in this Logic App version for generating unique IDs