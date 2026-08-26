const { createDemoData } = require('./localDemoData');

const dd = createDemoData();
const countries = dd.countries;

function sum(metric) {
  return Object.fromEntries(countries.map((country) => [
    country,
    dd.data
      .filter((row) => row.metric === metric && row.country === country)
      .reduce((total, row) => total + row.value, 0),
  ]));
}

const metrics = process.argv.slice(2);
const selectedMetrics = metrics.length ? metrics : dd.metrics;
selectedMetrics.forEach((metric) => {
  console.log('
' + metric);
  const totals = sum(metric);
  countries.forEach((country) => console.log('  ' + country + ': ' + totals[country]));
});
