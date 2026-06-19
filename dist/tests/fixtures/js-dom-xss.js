// Fixture: js-dom-xss — unescaped HTML sinks vs escaped/safe sinks.

// (+) jQuery .html() built by concatenation with unescaped data
function renderRow(order) {
  $('#rows').html('<td>' + order.total + '</td>');
}

// (+) innerHTML assigned a bare identifier
function renderName(el, data) {
  el.innerHTML = data.name;
}

// (-) .text() is a safe sink (no HTML parsing)
function renderSafe(order) {
  $('#rows').text(order.total);
}

// (-) .html() but value routed through escapeHtml()
function renderEscaped(order) {
  $('#rows').html('<td>' + escapeHtml(order.total) + '</td>');
}