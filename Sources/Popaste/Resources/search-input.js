// Keep marked IME text out of every filtering path, including background refreshes.
function createCommittedSearch(input, onCommit) {
    let value = input.value;
    let composing = false;
    function commit() {
        if (value === input.value) return;
        value = input.value;
        onCommit(value);
    }
    input.addEventListener('compositionstart', () => { composing = true; });
    input.addEventListener('compositionend', () => {
        composing = false;
        commit();
    });
    input.addEventListener('input', event => {
        if (composing || event.isComposing) return;
        commit();
    });
    return {
        get value() { return value; },
        get isComposing() { return composing; },
        reset() { composing = false; value = ''; input.value = ''; }
    };
}
if (typeof module !== 'undefined') module.exports = createCommittedSearch;
