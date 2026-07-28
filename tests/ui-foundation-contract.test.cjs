const test = require('node:test');
const assert = require('node:assert/strict');
const React = require('react');
const { JSDOM } = require('jsdom');

const dom = new JSDOM('<!doctype html><html><body></body></html>', {
  url: 'https://terranex.test/',
});

for (const property of [
  'window',
  'document',
  'navigator',
  'HTMLElement',
  'HTMLInputElement',
  'HTMLButtonElement',
  'Element',
  'Node',
  'NodeFilter',
  'Event',
  'CustomEvent',
  'KeyboardEvent',
  'MouseEvent',
  'FocusEvent',
  'BeforeUnloadEvent',
  'PopStateEvent',
  'MutationObserver',
  'getComputedStyle',
]) {
  globalThis[property] = dom.window[property];
}

globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.PointerEvent = dom.window.PointerEvent ?? dom.window.MouseEvent;
globalThis.requestAnimationFrame = (callback) => setTimeout(callback, 0);
globalThis.cancelAnimationFrame = (id) => clearTimeout(id);
globalThis.ResizeObserver = class {
  observe() {}
  unobserve() {}
  disconnect() {}
};

for (const method of ['hasPointerCapture', 'setPointerCapture', 'releasePointerCapture']) {
  if (!HTMLElement.prototype[method]) {
    HTMLElement.prototype[method] = () => false;
  }
}

const {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} = require('@testing-library/react');
const userEvent = require('@testing-library/user-event').default;
const {
  AdaptiveFormSurface,
  ConfirmDialog,
  EntityInspectorDrawer,
  FormActions,
  FormErrorSummary,
  UnsavedChangesGuard,
} = require('../src/components/ui/index.ts');
const {
  WorkspaceShell,
  useWorkspaceUrlState,
} = require('../src/components/workspace/index.ts');

test.afterEach(() => {
  cleanup();
  document.body.removeAttribute('style');
  document.body.removeAttribute('data-scroll-locked');
  window.history.replaceState(null, '', '/');
});

test('adaptive surface traps focus, closes with Escape, and restores focus', async () => {
  const user = userEvent.setup({ document });

  function Harness() {
    const [open, setOpen] = React.useState(false);
    return React.createElement(
      React.Fragment,
      null,
      React.createElement(
        'button',
        { type: 'button', onClick: () => setOpen(true) },
        'Open editor',
      ),
      React.createElement('button', { type: 'button' }, 'Outside'),
      React.createElement(
        AdaptiveFormSurface,
        {
          open,
          onOpenChange: setOpen,
          title: 'Edit asset',
          description: 'Update the selected asset',
          closeLabel: 'Close editor',
          cancelLabel: 'Cancel',
          submitLabel: 'Save',
        },
        React.createElement('input', { 'aria-label': 'Asset name' }),
      ),
    );
  }

  render(React.createElement(Harness));
  const trigger = screen.getByRole('button', { name: 'Open editor' });
  await user.click(trigger);

  const dialog = screen.getByRole('dialog', { name: 'Edit asset' });
  assert.ok(dialog.contains(document.activeElement));

  for (let index = 0; index < 6; index += 1) {
    await user.tab();
    assert.ok(dialog.contains(document.activeElement));
  }

  await user.keyboard('{Escape}');
  await waitFor(() => assert.equal(screen.queryByRole('dialog'), null));
  assert.equal(document.activeElement, trigger);
});

test('adaptive surface blocks duplicate async submits and closing while pending', async () => {
  let submissions = 0;
  let resolveSubmission;
  const submission = new Promise((resolve) => {
    resolveSubmission = resolve;
  });
  const onOpenChangeCalls = [];

  render(
    React.createElement(
      AdaptiveFormSurface,
      {
        open: true,
        onOpenChange: (next) => onOpenChangeCalls.push(next),
        title: 'Create project',
        description: 'Project details',
        closeLabel: 'Close',
        cancelLabel: 'Cancel',
        submitLabel: 'Create',
        onSubmit: () => {
          submissions += 1;
          return submission;
        },
      },
      React.createElement('p', null, 'Form body'),
    ),
  );

  const submit = screen.getByRole('button', { name: 'Create' });
  fireEvent.click(submit);
  fireEvent.click(submit);

  assert.equal(submissions, 1);
  assert.equal(submit.disabled, true);
  fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' });
  assert.deepEqual(onOpenChangeCalls, []);

  await act(async () => resolveSubmission());
  await waitFor(() => assert.equal(submit.disabled, false));
});

test('confirm dialog names the impact and locks a destructive async action', async () => {
  let confirmations = 0;
  let resolveConfirmation;
  const confirmation = new Promise((resolve) => {
    resolveConfirmation = resolve;
  });

  render(
    React.createElement(ConfirmDialog, {
      open: true,
      onOpenChange: () => {},
      title: 'Delete record',
      entityName: 'Project Atlas',
      impact: 'All linked draft data will be removed.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep',
      onConfirm: () => {
        confirmations += 1;
        return confirmation;
      },
    }),
  );

  assert.match(screen.getByRole('dialog').textContent, /Project Atlas/);
  assert.match(screen.getByRole('dialog').textContent, /linked draft data/);

  const confirm = screen.getByRole('button', { name: 'Delete' });
  fireEvent.click(confirm);
  fireEvent.click(confirm);
  assert.equal(confirmations, 1);
  assert.equal(confirm.disabled, true);

  await act(async () => resolveConfirmation());
  await waitFor(() => assert.equal(confirm.disabled, false));
});

test('form contracts expose validation, server errors, pending, and read-only states', () => {
  const { rerender } = render(
    React.createElement(FormErrorSummary, {
      title: 'Could not save',
      serverError: 'Supabase rejected the write',
      errors: {
        name: { type: 'required', message: 'Name is required' },
        nested: {
          amount: { type: 'min', message: 'Amount must be positive' },
        },
      },
    }),
  );

  const alert = screen.getByRole('alert');
  assert.match(alert.textContent, /Supabase rejected the write/);
  assert.match(alert.textContent, /Name is required/);
  assert.match(alert.textContent, /Amount must be positive/);
  assert.equal(alert.querySelectorAll('li').length, 3);

  rerender(
    React.createElement(FormActions, {
      cancelLabel: 'Cancel',
      submitLabel: 'Save',
      onCancel: () => {},
      pending: true,
    }),
  );
  assert.equal(screen.getByRole('button', { name: 'Cancel' }).disabled, true);
  assert.equal(screen.getByRole('button', { name: 'Save' }).disabled, true);

  rerender(
    React.createElement(FormActions, {
      cancelLabel: 'Close',
      submitLabel: 'Save',
      onCancel: () => {},
      readOnly: true,
    }),
  );
  assert.equal(screen.queryByRole('button', { name: 'Save' }), null);
});

test('unsaved changes guard blocks beforeunload and requires explicit discard', async () => {
  const user = userEvent.setup({ document });
  let discarded = 0;

  function Harness() {
    const [open, setOpen] = React.useState(true);
    return React.createElement(UnsavedChangesGuard, {
      dirty: true,
      open,
      onOpenChange: setOpen,
      onDiscard: () => {
        discarded += 1;
        setOpen(false);
      },
      title: 'Discard changes?',
      entityName: 'Asset form',
      impact: 'Your edits have not been saved.',
      discardLabel: 'Discard',
      keepEditingLabel: 'Keep editing',
    });
  }

  render(React.createElement(Harness));
  const beforeUnload = new window.Event('beforeunload', {
    cancelable: true,
  });
  assert.equal(window.dispatchEvent(beforeUnload), false);
  assert.equal(beforeUnload.defaultPrevented, true);

  await user.click(screen.getByRole('button', { name: 'Discard' }));
  assert.equal(discarded, 1);
  await waitFor(() => assert.equal(screen.queryByRole('dialog'), null));
});

test('workspace URL state preserves history state and follows back navigation', async () => {
  const user = userEvent.setup({ document });
  const workspaces = ['overview', 'assets'];
  window.history.replaceState({ requestId: 'keep-me' }, '', '/?workspace=overview');

  function Harness() {
    const [workspace, selectWorkspace] = useWorkspaceUrlState(
      workspaces,
      'overview',
      { replace: false },
    );
    return React.createElement(
      React.Fragment,
      null,
      React.createElement('output', null, workspace),
      React.createElement(
        'button',
        { type: 'button', onClick: () => selectWorkspace('assets') },
        'Choose assets',
      ),
    );
  }

  render(React.createElement(Harness));
  await user.click(screen.getByRole('button', { name: 'Choose assets' }));
  assert.equal(screen.getByText('assets').textContent, 'assets');
  assert.equal(new URL(window.location.href).searchParams.get('workspace'), 'assets');
  assert.equal(window.history.state.requestId, 'keep-me');

  await act(async () => {
    window.history.back();
    await new Promise((resolve) => setTimeout(resolve, 0));
  });
  await waitFor(() => assert.equal(screen.getByText('overview').textContent, 'overview'));
});

test('workspace shell renders responsive switchers and each content state', () => {
  const workspaces = [
    { id: 'overview', label: 'Overview' },
    { id: 'assets', label: 'Assets' },
  ];
  const baseProps = {
    title: 'Portfolio',
    workspaces,
    activeWorkspace: 'overview',
    onWorkspaceChange: () => {},
    switcherLabel: 'Portfolio workspaces',
    loadingLabel: 'Loading portfolio',
  };

  const view = render(
    React.createElement(
      WorkspaceShell,
      baseProps,
      React.createElement('p', null, 'Ready content'),
    ),
  );

  const select = screen.getByRole('combobox', { name: 'Portfolio workspaces' });
  const navigation = screen.getByRole('navigation', { name: 'Portfolio workspaces' });
  assert.match(select.parentElement.className, /md:hidden/);
  assert.match(navigation.className, /hidden md:block/);
  assert.equal(screen.getByText('Ready content').textContent, 'Ready content');

  view.rerender(
    React.createElement(
      WorkspaceShell,
      { ...baseProps, state: 'loading' },
      React.createElement('p', null, 'Hidden content'),
    ),
  );
  assert.equal(screen.getByRole('status', { name: 'Loading portfolio' }) !== null, true);
  assert.equal(screen.queryByText('Hidden content'), null);

  view.rerender(
    React.createElement(
      WorkspaceShell,
      {
        ...baseProps,
        state: 'empty',
        emptyState: { title: 'No assets', description: 'Create the first asset.' },
      },
      null,
    ),
  );
  assert.equal(screen.getByText('No assets').textContent, 'No assets');

  view.rerender(
    React.createElement(
      WorkspaceShell,
      {
        ...baseProps,
        state: 'error',
        errorState: { title: 'Load failed', description: 'Try again.' },
      },
      null,
    ),
  );
  assert.match(screen.getByRole('alert').textContent, /Load failed/);
});

test('entity inspector renders optional relationships, activity, actions, and deep link', () => {
  render(
    React.createElement(EntityInspectorDrawer, {
      open: true,
      onOpenChange: () => {},
      title: 'Asset inspector',
      closeLabel: 'Close inspector',
      summary: React.createElement('p', null, 'Asset summary'),
      relationshipsLabel: 'Linked records',
      relationships: React.createElement('p', null, 'Project Atlas'),
      activityLabel: 'Recent changes',
      activity: React.createElement('p', null, 'Updated today'),
      actions: React.createElement('button', { type: 'button' }, 'Edit'),
      fullWorkspaceLink: { label: 'Open workspace', href: '/assets/atlas' },
    }),
  );

  const dialog = screen.getByRole('dialog', { name: 'Asset inspector' });
  assert.match(dialog.textContent, /Asset summary/);
  assert.match(dialog.textContent, /Linked records/);
  assert.match(dialog.textContent, /Recent changes/);
  assert.equal(
    screen.getByRole('link', { name: 'Open workspace' }).getAttribute('href'),
    '/assets/atlas',
  );
});
