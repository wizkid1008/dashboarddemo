// data/dashboardData.js
//
// Local demo data provider. This GitHub sample intentionally avoids live
// external data-service connections and keeps all dashboard data in-repo.
// Sets window.DD: { countries, districts, schools, years, metrics, metricTypes, data }
// Dispatches 'dd:ready' on document when complete.

window.DD = null;
window.DD_KPI13 = [];

(() => {
  const countries = ['Ghana', 'Malawi', 'Tanzania', 'Zambia', 'Zimbabwe'];
  const districts = {
    Ghana: ['Accra Metro', 'Tamale', 'Kumasi'],
    Malawi: ['Lilongwe', 'Blantyre', 'Dedza'],
    Tanzania: ['Arusha', 'Dodoma', 'Morogoro'],
    Zambia: ['Lusaka', 'Chipata', 'Kabwe'],
    Zimbabwe: ['Harare', 'Bulawayo', 'Mutare'],
  };
  const years = Array.from({ length: 11 }, (_, index) => 2020 + index);
  const metrics = [
    'Children Supported in School with Education Bursaries',
    'CAMA Members',
    'Active Learner Guides',
    'Number of Clients by Form',
    'Active Partner Schools',
    'Post School Clients',
    'Grants Disbursed',
    'Loans Disbursed',
    'Women Supported in Tertiary Education',
  ];
  const metricTypes = {
    'Children Supported in School with Education Bursaries': 'Count',
    'CAMA Members': 'Count',
    'Active Learner Guides': 'Count',
    'Number of Clients by Form': 'Count',
    'Active Partner Schools': 'Count',
    'Post School Clients': 'Count',
    'Grants Disbursed': 'Currency (USD)',
    'Loans Disbursed': 'Currency (USD)',
    'Women Supported in Tertiary Education': 'Count',
  };
  const countryBase = {
    Ghana: 0.92,
    Malawi: 1.08,
    Tanzania: 1.18,
    Zambia: 0.86,
    Zimbabwe: 1.03,
  };
  const metricBase = {
    'Children Supported in School with Education Bursaries': 1450,
    'CAMA Members': 2200,
    'Active Learner Guides': 180,
    'Number of Clients by Form': 3100,
    'Active Partner Schools': 46,
    'Post School Clients': 980,
    'Grants Disbursed': 12500,
    'Loans Disbursed': 8200,
    'Women Supported in Tertiary Education': 120,
  };

  const schools = {};
  const rows = [];

  countries.forEach((country, countryIndex) => {
    districts[country].forEach((district, districtIndex) => {
      schools[district] = [
        district + ' Demonstration School',
        district + ' Community Secondary',
        district + ' Partner Primary',
      ];

      schools[district].forEach((school, schoolIndex) => {
        years.forEach((year, yearIndex) => {
          metrics.forEach((metric, metricIndex) => {
            const value = Math.round(
              metricBase[metric] *
              countryBase[country] *
              (1 + yearIndex * 0.045) *
              (0.74 + districtIndex * 0.18 + schoolIndex * 0.09) *
              (1 + metricIndex * 0.012)
            );

            rows.push({
              country,
              district,
              school,
              year,
              metric,
              value_type: metricTypes[metric],
              value,
              source: 'Local demo data',
            });
          });
        });
      });
    });
  });

  window.DD_KPI13 = countries.flatMap((country) =>
    years.flatMap((year, yearIndex) => [
      {
        country,
        gender: 'Girls',
        year,
        value: Math.round(12000 * countryBase[country] * (1 + yearIndex * 0.035)),
      },
      {
        country,
        gender: 'Boys',
        year,
        value: Math.round(9800 * countryBase[country] * (1 + yearIndex * 0.032)),
      },
    ])
  );

  window.DD = {
    countries,
    districts,
    schools,
    years,
    metrics,
    metricTypes,
    data: rows,
  };

  document.dispatchEvent(new CustomEvent('dd:ready'));
})();

