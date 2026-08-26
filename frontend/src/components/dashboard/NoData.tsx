export function NoData() {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      height: '100%', minHeight: 80,
      color: 'var(--text-mid)', fontSize: '0.83rem', fontStyle: 'italic',
      textAlign: 'center', padding: '24px 16px',
    }}>
      No data is available for this KPI during this time period
    </div>
  )
}
