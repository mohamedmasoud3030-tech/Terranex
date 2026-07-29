const test = require('node:test');
const assert = require('node:assert/strict');
const React = require('react');
const { JSDOM } = require('jsdom');

const dom = new JSDOM('<!doctype html><html><body></body></html>', {
  url: 'https://terranex.test/portfolio',
});

for (const property of [
  'window',
  'document',
  'navigator',
  'HTMLElement',
  'HTMLInputElement',
  'HTMLButtonElement',
  'HTMLSelectElement',
  'Element',
  'Node',
  'NodeFilter',
  'Event',
  'CustomEvent',
  'KeyboardEvent',
  'MouseEvent',
  'FocusEvent',
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

const { cleanup, render, screen } = require('@testing-library/react');
const userEvent = require('@testing-library/user-event').default;
const { AssetForm } = require('../src/features/assets/AssetForm.tsx');
const { ProjectWorkspaceView } = require('../src/features/portfolio/ProjectWorkspaceView.tsx');
const {
  AssetsWorkspace,
  PartnersWorkspace,
  ProjectsWorkspace,
} = require('../src/features/portfolio/PortfolioWorkspaces.tsx');

test.afterEach(() => cleanup());

const projects = [
  {
    id: 'project-1',
    sector_id: 'real-estate',
    name_ar: 'المشروع العقاري',
    name_en: 'Real estate project',
    status: 'active',
    start_date: '2026-01-01',
    base_currency: 'EGP',
    created_at: '2026-01-01',
    updated_at: '2026-01-01',
  },
  {
    id: 'project-2',
    sector_id: 'livestock',
    name_ar: 'مشروع القطيع',
    name_en: 'Herd project',
    status: 'active',
    start_date: '2026-01-01',
    base_currency: 'OMR',
    created_at: '2026-01-01',
    updated_at: '2026-01-01',
  },
];

test('asset form preserves project prefill, locks project context, and derives sector', () => {
  render(React.createElement(AssetForm, {
    formId: 'asset-form',
    projects,
    projectLock: 'project-2',
    locale: 'en',
    onSubmit: () => {},
    onCancel: () => {},
  }));

  const project = screen.getByRole('combobox', { name: 'Project *' });
  assert.equal(project.value, 'project-2');
  assert.equal(project.disabled, true);
  assert.equal(screen.getByRole('textbox', { name: 'Project sector' }).value, 'livestock');
});

test('project workspace is continuous section navigation and emits typed contextual handoff', async () => {
  const handoffs = [];
  const user = userEvent.setup({ document });
  render(React.createElement(ProjectWorkspaceView, {
    project: projects[0],
    assets: [],
    partners: [],
    projectPartners: [],
    transactions: [],
    obligations: [],
    documents: [],
    events: [],
    locale: 'en',
    embedded: true,
    onAddAsset: () => {},
    onHandoff: (handoff) => handoffs.push(handoff),
  }));

  const navigation = screen.getByRole('navigation', { name: 'Project sections' });
  assert.equal(navigation.querySelectorAll('a').length, 6);
  assert.equal(screen.queryByRole('tablist'), null);
  await user.click(screen.getByRole('button', { name: 'Financial entry' }));
  assert.deepEqual(handoffs, [{
    target: 'finance',
    workspace: 'transactions',
    context: { projectId: 'project-1', sector: 'real-estate' },
    intent: 'create-transaction',
  }]);
});

test('portfolio workspaces expose mobile-safe filters and master-detail actions', () => {
  const noop = () => {};
  const view = render(React.createElement(ProjectsWorkspace, {
    projects,
    transactions: [],
    obligations: [],
    projectPartners: [],
    partners: [],
    locale: 'en',
    query: '',
    sector: 'all',
    status: 'all',
    onQuery: noop,
    onSector: noop,
    onStatus: noop,
    onInspect: noop,
    onOpenWorkspace: noop,
  }));
  assert.ok(screen.getByRole('searchbox', { name: 'Search projects' }).className.includes('min-h-11'));
  assert.equal(screen.getAllByRole('button', { name: 'Quick view' }).length, 2);
  assert.equal(screen.getAllByRole('button', { name: 'Project workspace' }).length, 2);

  view.rerender(React.createElement(AssetsWorkspace, {
    assets: [],
    projects,
    locale: 'en',
    query: '',
    projectId: 'all',
    sector: 'all',
    type: 'all',
    status: 'all',
    onQuery: noop,
    onProject: noop,
    onSector: noop,
    onType: noop,
    onStatus: noop,
    onInspect: noop,
  }));
  assert.ok(screen.getByRole('searchbox', { name: 'Search assets' }).className.includes('min-h-11'));

  view.rerender(React.createElement(PartnersWorkspace, {
    partners: [],
    obligations: [],
    projectPartners: [],
    locale: 'en',
    query: '',
    category: 'all',
    onQuery: noop,
    onCategory: noop,
    onInspect: noop,
    onOpenWorkspace: noop,
  }));
  assert.ok(screen.getByRole('searchbox', { name: 'Search partners' }).className.includes('min-h-11'));
});
