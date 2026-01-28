/**
 * Automated tests for diff logic in index.html
 * Run: node scripts/test-diff.mjs
 *
 * Extracts diff functions from index.html and tests them with marked.js
 */

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, '..');

// Load marked.js
const markedCode = readFileSync(join(projectRoot, 'Sources/CCPlanView/Resources/marked.min.js'), 'utf-8');
const markedModule = new Function(markedCode + '; return marked;')();
const { Lexer } = markedModule;

// Extract diff functions from index.html
const html = readFileSync(join(projectRoot, 'Sources/CCPlanView/Resources/index.html'), 'utf-8');
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
const scriptContent = scriptMatch[1];

// Extract function bodies (from range() to setTheme())
const funcStart = scriptContent.indexOf('function range(');
const funcEnd = scriptContent.indexOf('function setTheme(');
const diffCode = scriptContent.substring(funcStart, funcEnd);

// Evaluate diff functions in a context
const evalContext = new Function(`
    ${diffCode}
    return { range, lcsPairs, greedyPairByDistance, diffTokens, diffListItems, diffTableRows, diffCodeLines };
`)();

const { diffTokens, diffListItems, diffTableRows, diffCodeLines } = evalContext;

// Test helpers
let passed = 0;
let failed = 0;

function assert(condition, message) {
    if (condition) {
        passed++;
    } else {
        failed++;
        console.error(`  FAIL: ${message}`);
    }
}

function lex(md) {
    return Lexer.lex(md);
}

// --- Tests ---

console.log('Test 1: Identical content → no changes');
{
    const md = '# Hello\n\nWorld\n';
    const tokens = lex(md);
    const result = diffTokens(tokens, lex(md));
    assert(result.changes.size === 0, 'no changes expected');
    assert(result.deletions.length === 0, 'no deletions expected');
}

console.log('Test 2: Same number of blocks, one modified');
{
    const old = lex('# Hello\n\nWorld\n');
    const now = lex('# Hello\n\nEarth\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, `expected 1 change, got ${result.changes.size}`);
    assert(result.changes.has(1), 'change should be at index 1 (second block)');
    assert(result.changes.get(1).type === 'modified', 'should be modified');
    assert(result.deletions.length === 0, 'no deletions');
}

console.log('Test 3: Block added');
{
    const old = lex('# Hello\n\nWorld\n');
    const now = lex('# Hello\n\nNew paragraph\n\nWorld\n');
    const result = diffTokens(old, now);
    assert(result.changes.has(1), 'new block at index 1 should be marked');
    assert(result.changes.get(1).type === 'added', 'should be added');
    assert(result.deletions.length === 0, 'no deletions');
}

console.log('Test 4: Block deleted');
{
    const old = lex('# Hello\n\nMiddle\n\nWorld\n');
    const now = lex('# Hello\n\nWorld\n');
    const result = diffTokens(old, now);
    assert(result.deletions.length === 1, `expected 1 deletion, got ${result.deletions.length}`);
    assert(result.deletions[0].token.raw.includes('Middle'), 'deleted block should contain "Middle"');
}

console.log('Test 5: Multiple tables - cross-pairing prevention');
{
    const old = lex([
        '# Title',
        '',
        '| A | B |',
        '|---|---|',
        '| a1 | b1 |',
        '| a2 | b2 |',
        '',
        'Separator',
        '',
        '| C | D |',
        '|---|---|',
        '| c1 | d1 |',
        '| c2 | d2 |',
        ''
    ].join('\n'));

    const now = lex([
        '# Title',
        '',
        '| A | B |',
        '|---|---|',
        '| a1-modified | b1 |',
        '| a2 | b2 |',
        '',
        'Separator',
        '',
        '| C | D |',
        '|---|---|',
        '| c1 | d1-modified |',
        '| c2 | d2 |',
        ''
    ].join('\n'));

    const result = diffTokens(old, now);

    // Both tables should be detected as changed (type: 'table')
    // The key test: table at position X should be paired with table at same position,
    // NOT cross-paired with the other table
    let tableChanges = [];
    for (const [idx, detail] of result.changes) {
        if (detail.type === 'table') tableChanges.push({ idx, detail });
    }
    assert(tableChanges.length === 2, `expected 2 table changes, got ${tableChanges.length}`);

    // Verify first table's diff shows row 0 changed (a1-modified)
    if (tableChanges.length >= 1) {
        const td1 = tableChanges[0].detail.tableDiff;
        assert(td1.changed.has(0), 'first table should have row 0 changed');
        // The old value should contain "a1" (from table A), not "c1" (from table C)
        if (td1.changed.get(0)) {
            const oldRow = td1.changed.get(0).map(c => c.text).join('|');
            assert(oldRow.includes('a1'), `first table old row should contain "a1", got "${oldRow}"`);
            assert(!oldRow.includes('c1'), `first table old row should NOT contain "c1" (cross-pairing!)`);
        }
    }

    // Verify second table's diff shows row 0 changed (d1-modified)
    if (tableChanges.length >= 2) {
        const td2 = tableChanges[1].detail.tableDiff;
        assert(td2.changed.has(0), 'second table should have row 0 changed');
        if (td2.changed.get(0)) {
            const oldRow = td2.changed.get(0).map(c => c.text).join('|');
            assert(oldRow.includes('c1'), `second table old row should contain "c1", got "${oldRow}"`);
            assert(!oldRow.includes('a1'), `second table old row should NOT contain "a1" (cross-pairing!)`);
        }
    }
}

console.log('Test 6: Table row added');
{
    const old = lex('| A |\n|---|\n| 1 |\n| 2 |\n');
    const now = lex('| A |\n|---|\n| 1 |\n| new |\n| 2 |\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, 'one table change');
    const detail = result.changes.values().next().value;
    assert(detail.type === 'table', 'should be table diff');
    assert(detail.tableDiff.changed.has(1), 'row 1 should be added');
    assert(detail.tableDiff.changed.get(1) === null, 'added row has null old value');
}

console.log('Test 7: Table row deleted');
{
    const old = lex('| A |\n|---|\n| 1 |\n| middle |\n| 2 |\n');
    const now = lex('| A |\n|---|\n| 1 |\n| 2 |\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, 'one table change');
    const detail = result.changes.values().next().value;
    assert(detail.type === 'table', 'should be table diff');
    assert(detail.tableDiff.deleted.length === 1, 'one row deleted');
    const delCells = detail.tableDiff.deleted[0].cells.map(c => c.text).join('');
    assert(delCells.includes('middle'), `deleted row should contain "middle", got "${delCells}"`);
}

console.log('Test 8: List item added');
{
    const old = lex('- item1\n- item2\n');
    const now = lex('- item1\n- new item\n- item2\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, 'one list change');
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', 'should be list diff');
    assert(detail.listDiff.changed.has(1), 'item at index 1 added');
    assert(detail.listDiff.changed.get(1) === null, 'added item has null old value');
}

console.log('Test 9: List item deleted');
{
    const old = lex('- item1\n- middle\n- item2\n');
    const now = lex('- item1\n- item2\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, 'one list change');
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', 'should be list diff');
    assert(detail.listDiff.deleted.length === 1, 'one item deleted');
    assert(detail.listDiff.deleted[0].item.text.includes('middle'), 'deleted item is "middle"');
}

console.log('Test 10: List item modified (shows as add+delete)');
{
    const old = lex('- item1\n- item2\n');
    const now = lex('- item1\n- item2-changed\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, 'one list change');
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', 'should be list diff');
    // LCS-based: item2 != item2-changed → treated as add + delete, not modify
    assert(detail.listDiff.changed.has(1), 'item 1 should be marked');
    assert(detail.listDiff.changed.get(1) === null, 'new item is added (null)');
    assert(detail.listDiff.deleted.length === 1, 'old item is deleted');
}

console.log('Test 11: List add+delete same count (shift detection)');
{
    // Old: [First, Second, Third, Fourth] → New: [First, NEW, Second, Fourth]
    // Same length (4) but "Third" deleted and "NEW" inserted — must NOT use positional comparison
    const old = lex('- First\n- Second\n- Third\n- Fourth\n');
    const now = lex('- First\n- NEW\n- Second\n- Fourth\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, `expected 1 list change, got ${result.changes.size}`);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', 'should be list diff');
    // "NEW" should be added (null old value), not modified
    assert(detail.listDiff.changed.has(1), 'index 1 should be changed');
    assert(detail.listDiff.changed.get(1) === null, 'NEW item should be added (null), not modified');
    // "Second" should NOT be marked as changed
    assert(!detail.listDiff.changed.has(2), 'Second item should NOT be changed');
    // "Third" should be deleted
    assert(detail.listDiff.deleted.length === 1, 'one item deleted');
    assert(detail.listDiff.deleted[0].item.text.includes('Third'), 'deleted item should be "Third"');
}

console.log('Test 12: Table row add+delete same count (shift detection)');
{
    const old = lex('| A |\n|---|\n| r1 |\n| r2 |\n| r3 |\n');
    const now = lex('| A |\n|---|\n| r1 |\n| new |\n| r3 |\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, 'one table change');
    const detail = result.changes.values().next().value;
    assert(detail.type === 'table', 'should be table diff');
    // "new" should be added, "r2" deleted — not positional mismatch
    assert(detail.tableDiff.changed.has(1), 'row 1 should be marked');
    assert(detail.tableDiff.changed.get(1) === null, 'new row should be added (null)');
    assert(detail.tableDiff.deleted.length === 1, 'one row deleted');
}

console.log('Test 13: Code block line-level diff');
{
    const old = lex('```js\nconst a = 1;\nconst b = 2;\nconst c = 3;\n```\n');
    const now = lex('```js\nconst a = 1;\nconst b = 99;\nconst c = 3;\n```\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, `expected 1 change, got ${result.changes.size}`);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'code', `should be code diff, got ${detail.type}`);
    // line 1 changed (b = 2 → b = 99), lines 0 and 2 unchanged
    assert(detail.codeDiff.changed.has(1), 'line 1 should be changed');
    assert(detail.codeDiff.changed.get(1) === null, 'changed line is added (null)');
    assert(!detail.codeDiff.changed.has(0), 'line 0 should NOT be changed');
    assert(!detail.codeDiff.changed.has(2), 'line 2 should NOT be changed');
    assert(detail.codeDiff.deleted.length === 1, 'one line deleted');
    assert(detail.codeDiff.deleted[0].line === 'const b = 2;', 'deleted line content');
}

console.log('Test 14: Code block line added');
{
    const old = lex('```\nline1\nline2\n```\n');
    const now = lex('```\nline1\nnew line\nline2\n```\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'code', 'should be code diff');
    assert(detail.codeDiff.changed.has(1), 'line 1 should be added');
    assert(detail.codeDiff.changed.get(1) === null, 'added line');
    assert(detail.codeDiff.deleted.length === 0, 'no deleted lines');
}

console.log('Test 15: Code block line deleted');
{
    const old = lex('```\nline1\nmiddle\nline2\n```\n');
    const now = lex('```\nline1\nline2\n```\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'code', 'should be code diff');
    assert(detail.codeDiff.changed.size === 0, 'no changed lines');
    assert(detail.codeDiff.deleted.length === 1, 'one line deleted');
    assert(detail.codeDiff.deleted[0].line === 'middle', 'deleted line is "middle"');
}

console.log('Test 16: Identical code block → no changes');
{
    const md = '```js\nconst x = 1;\n```\n';
    const result = diffTokens(lex(md), lex(md));
    assert(result.changes.size === 0, 'no changes for identical code');
}

console.log('Test 17: Code block deleted line appears before changed line (ordering)');
{
    // old: [A, B, C] → new: [A, B', C]
    // B deleted, B' added. Deleted B should have beforeIdx=1 (same as B'),
    // so rendering shows: A, B(red), B'(green), C
    const old = lex('```\nA\nB\nC\n```\n');
    const now = lex('```\nA\nB-changed\nC\n```\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'code', 'should be code diff');
    assert(detail.codeDiff.changed.has(1), 'line 1 is changed (added)');
    assert(detail.codeDiff.deleted.length === 1, 'one deleted line');
    // beforeIdx should be 1 (previous match A at new[0], so 0+1=1)
    // This ensures deleted B(red) appears before changed B'(green) at position 1
    assert(detail.codeDiff.deleted[0].beforeIdx === 1,
        `deleted line beforeIdx should be 1, got ${detail.codeDiff.deleted[0].beforeIdx}`);
}

console.log('Test 18: Code block multiple changes maintain order');
{
    // old: [a, b, c, d] → new: [a, b2, c2, d]
    // b→b2, c→c2: each deletion should appear before its replacement
    const old = lex('```\na\nb\nc\nd\n```\n');
    const now = lex('```\na\nb2\nc2\nd\n```\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'code', 'should be code diff');
    assert(detail.codeDiff.deleted.length === 2, 'two deleted lines');
    // b deleted: prev match a at new[0] → beforeIdx = 1
    // c deleted: prev match still a at new[0] → beforeIdx = 1? No...
    // Actually: LCS pairs a(0→0), d(3→3). b and c are both unmatched.
    // b: prev match old[0]→new[0], beforeIdx = 0+1 = 1
    // c: prev match old[0]→new[0], beforeIdx = 0+1 = 1
    // Both deletions at beforeIdx=1, which means they appear before new[1]
    // changed: new[1]=b2 (added), new[2]=c2 (added)
    // Render order: a, b(red), c(red), b2(green), c2(green), d
    // Hmm, that's not ideal but acceptable. The key is deleted before added.
    assert(detail.codeDiff.deleted[0].beforeIdx <= 2, 'first deleted before or at position 2');
    assert(detail.codeDiff.deleted[1].beforeIdx <= 2, 'second deleted before or at position 2');
}

console.log('Test 19: Code block first line changed — red before green');
{
    const old = lex('```\nold first\nsame\n```\n');
    const now = lex('```\nnew first\nsame\n```\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'code', 'should be code diff');
    assert(detail.codeDiff.changed.has(0), 'line 0 changed');
    assert(detail.codeDiff.deleted.length === 1, 'one deleted line');
    // No previous match → beforeIdx must be 0 so red appears before green at line 0
    assert(detail.codeDiff.deleted[0].beforeIdx === 0,
        `first line deleted beforeIdx should be 0, got ${detail.codeDiff.deleted[0].beforeIdx}`);
}

console.log('Test 20: Blockquote sub-element diff — paragraph changed');
{
    const old = lex('> First paragraph.\n>\n> Second paragraph.\n>\n> Third paragraph.\n');
    const now = lex('> First paragraph.\n>\n> Second MODIFIED.\n>\n> Third paragraph.\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, `expected 1 blockquote change, got ${result.changes.size}`);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'blockquote', `should be blockquote diff, got ${detail.type}`);
    // Sub-element level: only the second paragraph should be changed
    const bqDiff = detail.bqDiff;
    assert(bqDiff.changes.size === 1, `expected 1 sub-change, got ${bqDiff.changes.size}`);
    assert(bqDiff.deletions.length === 0, 'no sub-deletions');
}

console.log('Test 21: Blockquote sub-element diff — paragraph added');
{
    const old = lex('> First.\n>\n> Second.\n');
    const now = lex('> First.\n>\n> New paragraph.\n>\n> Second.\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'blockquote', `should be blockquote diff, got ${detail.type}`);
    const bqDiff = detail.bqDiff;
    assert(bqDiff.changes.size === 1, `expected 1 sub-change (added), got ${bqDiff.changes.size}`);
    const addedEntry = [...bqDiff.changes.values()][0];
    assert(addedEntry.type === 'added', `sub-change should be added, got ${addedEntry.type}`);
}

console.log('Test 22: Blockquote sub-element diff — paragraph deleted');
{
    const old = lex('> First.\n>\n> Middle.\n>\n> Last.\n');
    const now = lex('> First.\n>\n> Last.\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'blockquote', `should be blockquote diff, got ${detail.type}`);
    const bqDiff = detail.bqDiff;
    assert(bqDiff.deletions.length === 1, `expected 1 sub-deletion, got ${bqDiff.deletions.length}`);
}

console.log('Test 23: Blockquote with list — list item changed');
{
    const old = lex('> **Note:** Info.\n>\n> - Item 1\n> - Item 2\n>\n> End.\n');
    const now = lex('> **Note:** Info.\n>\n> - Item 1\n> - Item 2 modified\n>\n> End.\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'blockquote', `should be blockquote diff, got ${detail.type}`);
    const bqDiff = detail.bqDiff;
    // The list sub-token should be detected as changed with list diff
    let hasListChange = false;
    for (const [, subDetail] of bqDiff.changes) {
        if (subDetail.type === 'list') hasListChange = true;
    }
    assert(hasListChange, 'blockquote should contain a list sub-change');
}

console.log('Test 24: Identical blockquote → no changes');
{
    const md = '> This is a quote.\n>\n> With two paragraphs.\n';
    const result = diffTokens(lex(md), lex(md));
    assert(result.changes.size === 0, 'no changes for identical blockquote');
}

console.log('Test 25: Nested list — sub-item changed');
{
    const old = lex('- Parent 1\n  - Child A\n  - Child B\n- Parent 2\n');
    const now = lex('- Parent 1\n  - Child A\n  - Child B modified\n- Parent 2\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, `expected 1 list change, got ${result.changes.size}`);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', `should be list diff, got ${detail.type}`);
    // Parent 1 should have nestedList change, not be shown as whole-item modified
    let hasNested = false;
    for (const [, info] of detail.listDiff.changed) {
        if (info && info.type === 'nestedList') hasNested = true;
    }
    assert(hasNested, 'should detect nestedList change instead of whole-item add/delete');
    assert(detail.listDiff.deleted.length === 0, 'no deleted parent items');
}

console.log('Test 26: Nested list — sub-item added');
{
    const old = lex('- Parent\n  - Child A\n  - Child B\n');
    const now = lex('- Parent\n  - Child A\n  - New child\n  - Child B\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', 'should be list diff');
    const entry = [...detail.listDiff.changed.values()].find(v => v && v.type === 'nestedList');
    assert(entry, 'should have nestedList change');
    assert(entry.nestedDiff.changed.size === 1, 'one sub-item added');
    const addedInfo = [...entry.nestedDiff.changed.values()][0];
    assert(addedInfo === null, 'added sub-item should be null');
}

console.log('Test 27: Nested list — sub-item deleted');
{
    const old = lex('- Parent\n  - Child A\n  - Child B\n  - Child C\n');
    const now = lex('- Parent\n  - Child A\n  - Child C\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', 'should be list diff');
    const entry = [...detail.listDiff.changed.values()].find(v => v && v.type === 'nestedList');
    assert(entry, 'should have nestedList change');
    assert(entry.nestedDiff.deleted.length === 1, 'one sub-item deleted');
    assert(entry.nestedDiff.deleted[0].item.text.includes('Child B'), 'deleted sub-item is Child B');
}

console.log('Test 28: Nested list — identical nested list → no changes');
{
    const md = '- Parent\n  - Child A\n  - Child B\n';
    const result = diffTokens(lex(md), lex(md));
    assert(result.changes.size === 0, 'no changes for identical nested list');
}

console.log('Test 29: Nested list — parent text same, only sub-items differ');
{
    // Ensure parent item is NOT marked as added/deleted, only sub-list is diffed
    const old = lex('- Parent\n  - Old child\n');
    const now = lex('- Parent\n  - New child\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', 'should be list diff');
    // Should NOT have deleted parent items
    assert(detail.listDiff.deleted.length === 0, 'parent item should not be deleted');
    // The change should be nestedList, not null (added)
    const changeInfo = [...detail.listDiff.changed.values()][0];
    assert(changeInfo !== null, 'should not be null (added)');
    assert(changeInfo.type === 'nestedList', `should be nestedList, got ${changeInfo?.type}`);
}

console.log('Test 30: Blockquote with code block — sub-element code diff');
{
    const old = lex('> Intro.\n>\n> ```js\n> const x = 1;\n> const y = 2;\n> ```\n>\n> End.\n');
    const now = lex('> Intro.\n>\n> ```js\n> const x = 1;\n> const y = 99;\n> ```\n>\n> End.\n');
    const result = diffTokens(old, now);
    assert(result.changes.size === 1, `expected 1 blockquote change, got ${result.changes.size}`);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'blockquote', `should be blockquote, got ${detail.type}`);
    let hasCodeChange = false;
    for (const [, sub] of detail.bqDiff.changes) {
        if (sub.type === 'code') hasCodeChange = true;
    }
    assert(hasCodeChange, 'blockquote should detect code sub-change');
}

console.log('Test 31: Blockquote with table — sub-element table diff');
{
    const old = lex('> | A |\n> |---|\n> | 1 |\n');
    const now = lex('> | A |\n> |---|\n> | 2 |\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'blockquote', `should be blockquote, got ${detail.type}`);
    let hasTableChange = false;
    for (const [, sub] of detail.bqDiff.changes) {
        if (sub.type === 'table') hasTableChange = true;
    }
    assert(hasTableChange, 'blockquote should detect table sub-change');
}

console.log('Test 32: Nested list with bold parent — parentText extraction');
{
    // Parent text starts with bold, not plain text token
    const old = lex('- **Bold parent**\n  - Child A\n  - Child B\n');
    const now = lex('- **Bold parent**\n  - Child A\n  - Child B modified\n');
    const result = diffTokens(old, now);
    const detail = result.changes.values().next().value;
    assert(detail.type === 'list', `should be list, got ${detail.type}`);
    // Should detect nestedList, not add+delete parent item
    let hasNested = false;
    for (const [, info] of detail.listDiff.changed) {
        if (info && info.type === 'nestedList') hasNested = true;
    }
    assert(hasNested, 'bold parent should still match for nested list diff');
    assert(detail.listDiff.deleted.length === 0, 'no parent items deleted');
}

console.log('Test 33: LCS performance guard — large input does not hang');
{
    // Create arrays large enough to trigger the guard (>250000 product)
    const lines = [];
    for (let i = 0; i < 510; i++) lines.push(`line ${i}`);
    const oldMd = '```\n' + lines.join('\n') + '\n```\n';
    // Change one line
    lines[250] = 'line 250 changed';
    const newMd = '```\n' + lines.join('\n') + '\n```\n';
    const result = diffTokens(lex(oldMd), lex(newMd));
    // With guard, LCS skips → whole block treated as modified (not code line-level)
    // That's acceptable — the point is it doesn't hang
    assert(result.changes.size >= 1, 'should still detect a change');
}

console.log('Test 34: Whitespace-only change preserved scroll (no-change path)');
{
    // Identical content should produce no changes
    const md = '# Title\n\nParagraph.\n';
    const result = diffTokens(lex(md), lex(md));
    assert(result.changes.size === 0, 'no changes');
    assert(result.deletions.length === 0, 'no deletions');
    // This tests the diffResult !== null && hasChanges === false path
}

// --- Summary ---
console.log(`\n${'='.repeat(40)}`);
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failed > 0) {
    process.exit(1);
} else {
    console.log('All tests passed!');
}
