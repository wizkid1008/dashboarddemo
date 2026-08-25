const { createDemoData } = require('./localDemoData');

const dd = createDemoData();
console.log('Countries:', dd.countries.join(', '));
console.log('
Districts:');
Object.entries(dd.districts).forEach(([country, districts]) => {
  console.log('  ' + country + ': ' + districts.join(', '));
});
console.log('
Sample schools:');
Object.entries(dd.schools).slice(0, 5).forEach(([district, schools]) => {
  console.log('  ' + district + ': ' + schools.join(', '));
});
