const { test } = require('node:test');
const assert = require('node:assert/strict');
const createSearch = require('../Sources/Popaste/Resources/search-input.js');
function fixture(initial = '') {
    const input = new EventTarget(); input.value = initial;
    const changes = [];
    const search = createSearch(input, value => changes.push(value));
    const fire = (type, value = input.value, flags = {}) => {
        input.value = value;
        input.dispatchEvent(Object.assign(new Event(type), flags));
    };
    return { input, changes, search, fire };
}
test('Chinese marked text never reaches filtering; committed text applies once', () => {
    const { fire, changes, search } = fixture();
    fire('compositionstart');
    fire('input', 'n', { isComposing: true });
    fire('input', 'ni', { isComposing: true });
    fire('input', '你', { isComposing: true });
    assert.equal(search.value, ''); assert.deepEqual(changes, []);
    assert.equal(search.isComposing, true);
    fire('compositionend', '你');
    fire('input', '你', { isComposing: false });
    assert.equal(search.isComposing, false);
    assert.deepEqual(changes, ['你']);
});
test('unflagged inputs during composition also keep the committed query', () => {
    const { fire, changes, search } = fixture('你好');
    fire('compositionstart'); fire('input', '你好 shi', { isComposing: false });
    assert.equal(search.value, '你好'); assert.deepEqual(changes, []);
    fire('compositionend', '你好世界');
    assert.deepEqual(changes, ['你好世界']);
});
test('composition cancellation preserves the old query and selection callback', () => {
    const { fire, changes, search } = fixture('你好');
    fire('compositionstart'); fire('input', '你好 x', { isComposing: true });
    fire('compositionend', '你好'); fire('input', '你好');
    assert.equal(search.value, '你好'); assert.deepEqual(changes, []);
});
test('successive compositions commit separately, including final input before end', () => {
    const { fire, changes } = fixture();
    for (const value of ['你', '你好']) {
        fire('compositionstart'); fire('input', value, { isComposing: false });
        fire('compositionend', value);
    }
    assert.deepEqual(changes, ['你', '你好']);
});
test('ordinary typing, paste and deletion filter immediately', () => {
    const { fire, changes } = fixture();
    fire('input', 'a'); fire('input', '中文 🌟'); fire('input', '');
    assert.deepEqual(changes, ['a', '中文 🌟', '']);
});
test('reopening resets committed and visible query without retaining marked text', () => {
    const { fire, input, changes, search } = fixture('你');
    fire('compositionstart'); fire('input', '你 hao', { isComposing: true });
    search.reset();
    assert.equal(search.value, ''); assert.equal(input.value, '');
    assert.equal(search.isComposing, false);
    fire('input', 'hello'); assert.deepEqual(changes, ['hello']);
});
