// SamDrucker website: filter and sort result tables. Without JavaScript
// the pages still show every row; these only make long tables easier.

'use strict';

document.addEventListener('DOMContentLoaded', () => {
  // <input class="filter" data-table="ID">: hide rows of table ID which do
  // not contain the typed text.
  for (const input of document.querySelectorAll('input.filter[data-table]')) {
    const table = document.getElementById(input.dataset.table);
    if (!table) continue;
    input.addEventListener('input', () => {
      const needle = input.value.trim().toLowerCase();
      for (const row of table.tBodies[0].rows) {
        row.hidden = needle !== '' && !row.textContent.toLowerCase().includes(needle);
      }
    });
  }

  // <table class="sortable">: click a heading to sort by that column;
  // click again to reverse. A cell's data-sort attribute, when present,
  // is used instead of its text.
  for (const table of document.querySelectorAll('table.sortable')) {
    const headings = table.tHead.rows[0].cells;
    for (let col = 0; col < headings.length; col++) {
      const th = headings[col];
      th.tabIndex = 0;
      th.setAttribute('role', 'button');
      const sort = () => {
        const ascending = th.getAttribute('aria-sort') !== 'ascending';
        for (const other of headings) other.removeAttribute('aria-sort');
        th.setAttribute('aria-sort', ascending ? 'ascending' : 'descending');
        const numeric = th.classList.contains('num');
        const key = row => {
          const cell = row.cells[col];
          const v = cell.dataset.sort ?? cell.textContent.trim();
          return numeric ? Number(v) : v.toLowerCase();
        };
        const rows = Array.from(table.tBodies[0].rows);
        rows.sort((a, b) => {
          const x = key(a), y = key(b);
          const c = numeric ? x - y : x.localeCompare(y, undefined, { numeric: true });
          return ascending ? c : -c;
        });
        table.tBodies[0].append(...rows);
      };
      th.addEventListener('click', sort);
      th.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); sort(); } });
    }
  }
});
