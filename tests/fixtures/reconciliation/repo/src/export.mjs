// Uses the existing visible-row flag. Locale dates remain outstanding.
const quote = value => `"${String(value).replaceAll('"', '""')}"`;

export function exportReport(rows) {
  const lines = rows.filter(row => row.visible).map(row =>
    [row.name, new Date(row.date).toISOString()].map(quote).join(','));
  return ['name,date', ...lines].join('\n');
}
