// SamDrucker website: filter, sort and resize the columns of result
// tables. Without JavaScript the pages still show every row; these only
// make long tables easier.

'use strict';

// Column widths a viewer has chosen, kept in this browser only, per page
// and table. The key includes the column headings, so if a table's
// columns change, old widths are not applied to the wrong columns.
const COLUMN_MIN_WIDTH = 40;
const columnsKey = (table) =>
  'samdrucker-columns:' + location.pathname + ':' + table.id + ':' +
  Array.from(table.tHead.rows[0].cells, th => th.textContent.trim()).join('|');

function loadWidths(table) {
  try {
    const w = JSON.parse(localStorage.getItem(columnsKey(table)));
    return Array.isArray(w) ? w : null;
  } catch (e) {
    return null;
  }
}

function saveWidths(table, widths) {
  try {
    if (widths && widths.some(w => w)) {
      localStorage.setItem(columnsKey(table), JSON.stringify(widths));
    } else {
      localStorage.removeItem(columnsKey(table));
    }
  } catch (e) {
    // private window or storage blocked: the widths last until the page is left
  }
}

// Apply widths (pixels, or null for automatic) to the headings. Any width
// at all switches the table to fixed layout, where text which does not
// fit ends in an ellipsis. The last column always takes what is left.
function applyWidths(table, widths) {
  const headings = table.tHead.rows[0].cells;
  const fixed = widths !== null && widths.some(w => w);
  table.classList.toggle('fixed-columns', fixed);
  for (let i = 0; i < headings.length; i++) {
    const w = fixed && i < headings.length - 1 ? widths[i] : null;
    headings[i].style.width = w ? w + 'px' : '';
  }
  const reset = table.previousElementSibling;
  if (reset && reset.classList.contains('reset-columns')) {
    reset.hidden = !fixed;
  }
}

function makeResizable(table) {
  const headings = table.tHead.rows[0].cells;
  let widths = loadWidths(table);
  if (widths && widths.length !== headings.length) {
    widths = null;
  }

  // a "Reset columns" button just above the table, shown once a width is set
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.className = 'reset-columns';
  reset.textContent = 'Reset column widths';
  reset.addEventListener('click', () => {
    widths = null;
    saveWidths(table, null);
    applyWidths(table, null);
  });
  table.before(reset);
  applyWidths(table, widths);

  // a handle on the right edge of every heading but the last
  for (let col = 0; col < headings.length - 1; col++) {
    const th = headings[col];
    const handle = document.createElement('span');
    handle.className = 'column-resize';
    handle.title = 'Drag to resize; double-click for the automatic width';
    th.append(handle);

    // a click on the handle must not sort the column
    handle.addEventListener('click', e => e.stopPropagation());

    handle.addEventListener('pointerdown', e => {
      e.preventDefault();
      e.stopPropagation();
      // first resize: fix every column at the width it has now, so only
      // the one being dragged moves
      if (!widths || !widths.some(w => w)) {
        widths = Array.from(headings, h => Math.round(h.getBoundingClientRect().width));
      }
      const startX = e.clientX;
      const startWidth = widths[col] || Math.round(th.getBoundingClientRect().width);
      handle.setPointerCapture(e.pointerId);
      handle.classList.add('active');

      const move = ev => {
        widths[col] = Math.max(COLUMN_MIN_WIDTH, Math.round(startWidth + ev.clientX - startX));
        applyWidths(table, widths);
      };
      const end = () => {
        handle.classList.remove('active');
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', end);
        handle.removeEventListener('pointercancel', end);
        saveWidths(table, widths);
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', end);
      handle.addEventListener('pointercancel', end);
    });

    // double-click: this column back to its automatic width
    handle.addEventListener('dblclick', e => {
      e.stopPropagation();
      if (widths) {
        widths[col] = null;
        saveWidths(table, widths);
        applyWidths(table, widths);
      }
    });
  }

  // in fixed layout, show a cut-off value in full on hover
  table.tBodies[0].addEventListener('mouseover', e => {
    const cell = e.target.closest('td');
    if (cell && !cell.title && table.classList.contains('fixed-columns') &&
        cell.scrollWidth > cell.clientWidth) {
      cell.title = cell.textContent.trim();
    }
  });
}

document.addEventListener('DOMContentLoaded', () => {
  // Resizable columns on result tables, on screens wide enough to drag.
  // On narrow screens, tables scroll sideways instead (see the CSS).
  if (window.matchMedia('(min-width: 701px)').matches) {
    for (const table of document.querySelectorAll('table.sortable[id]')) {
      makeResizable(table);
    }
  }

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
