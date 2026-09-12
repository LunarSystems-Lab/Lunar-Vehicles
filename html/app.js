/* lunar-vehicles oil gauge. Copyright (C) 2026 Lunar. SPDX-License-Identifier: GPL-3.0-only */
(() => {
    const oil = document.getElementById('oil');
    const fill = document.getElementById('oil-fill');
    const level = document.getElementById('oil-level');

    function show() {
        oil.hidden = false;
        oil.setAttribute('aria-hidden', 'false');
        oil.classList.add('is-open');
    }

    function hide() {
        oil.classList.remove('is-open', 'is-warn', 'is-crit');
        oil.hidden = true;
        oil.setAttribute('aria-hidden', 'true');
    }

    function update(data) {
        data = data || {};
        const pct = Math.max(0, Math.min(100, Number(data.oil) || 0));
        fill.style.transform = 'scaleX(' + (pct / 100) + ')';
        level.textContent = Math.round(pct) + '%';
        oil.classList.remove('is-warn', 'is-crit');
        if (data.level === 'crit') oil.classList.add('is-crit');
        else if (data.level === 'warn') oil.classList.add('is-warn');
    }

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'oil') {
            if (d.open) show();
            else hide();
        }
        if (d.action === 'oilUpdate') {
            show();
            update(d.data || {});
        }
    });
})();
