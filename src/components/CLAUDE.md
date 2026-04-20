# src/components/ — Component Conventions

This directory contains all React components. It is split into two zones: `ui/` for shadcn/ui primitives and the top level for app-specific components.

## Directory Structure

```
src/components/
  ui/              — shadcn/ui components. Installed via CLI. Do NOT hand-edit.
    button.tsx
    card.tsx
    dialog.tsx
    ...
  DashboardShell.tsx   — App-specific component (PascalCase)
  UserAvatar.tsx       — App-specific component
  ...
  CLAUDE.md            — This file
```

## ui/ — shadcn/ui Components

The `ui/` subdirectory contains components installed by the shadcn CLI. These are copied into the project (not imported from node_modules) so they can be customized if needed.

**Rules**:

- Install components via `npx shadcn@latest add <component-name>`. Do NOT create component files in `ui/` by hand.
- Do NOT hand-edit files in `ui/` unless you have a specific customization requirement and understand the implications for future updates. If you must customize, document the change with a comment explaining why.
- To see available components: `npx shadcn@latest add --list`.

## App-Specific Components

Components that are specific to the application live directly in `src/components/` (not in `ui/`). These compose shadcn/ui primitives with application logic.

### How to Add a Component

1. **Create the file** with a PascalCase name: `src/components/ProjectCard.tsx`. This is an exception to the global `kebab-case` file naming rule, matching Next.js convention.

2. **Define explicit prop types**:

```typescript
type ProjectCardProps = {
  project: {
    id: string;
    name: string;
    description: string | null;
  };
  onSelect?: (id: string) => void;
};
```

3. **Export as a named export** (not default):

```typescript
export function ProjectCard({ project, onSelect }: ProjectCardProps) {
  return (
    <Card className="cursor-pointer" onClick={() => onSelect?.(project.id)}>
      <CardHeader>
        <CardTitle>{project.name}</CardTitle>
      </CardHeader>
      {project.description && (
        <CardContent>
          <p className="text-muted-foreground">{project.description}</p>
        </CardContent>
      )}
    </Card>
  );
}
```

4. **Add a unit test** in `tests/unit/` (e.g., `tests/unit/project-card.test.ts`).

### Component Rules

- **No `any` types**. Every prop, state, and callback is explicitly typed.
- **Use `cn()` from `@/lib/utils`** for conditional class names. Do not use string concatenation or template literals for Tailwind classes.
- **Named exports only**. No `export default`. This makes imports greppable and refactoring safer.
- **Server Components by default**. Only add `'use client'` when the component needs browser APIs, event handlers, or React hooks.
- **Composition over prop drilling**. Prefer children and render props over passing deeply nested data through multiple component layers.

### Accessibility

All interactive components must:

- Be keyboard navigable (focusable, operable with Enter/Space/Arrow keys as appropriate).
- Have ARIA labels where the visual label is insufficient or absent.
- Use semantic HTML elements (`button` for actions, `a` for navigation, `nav` for navigation regions).
- Pass axe-core AA checks in the page-level Playwright test.

shadcn/ui components handle most accessibility concerns out of the box. When composing them into app-specific components, verify that the composition does not break accessibility (e.g., wrapping a button in a div that swallows keyboard events).

### Import Conventions

```typescript
// 1. External dependencies
import { useState } from 'react';

// 2. Internal aliases — ui components
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

// 3. Internal aliases — utilities and types
import { cn } from '@/lib/utils';

// 4. Relative imports (colocated helpers, if any)
import { formatProjectDate } from './helpers';
```
