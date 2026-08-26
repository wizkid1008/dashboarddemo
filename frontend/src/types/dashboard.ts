export interface DashboardRow {
  country:  string
  province: string | null
  district: string
  school:   string
  /** NULL on district- and country-level rows, which have no school to classify. */
  school_type?: string | null
  metric:   string
  year:     number
  value:    number
}

export interface DashboardData {
  countries: string[]
  provinces: Record<string, string[]>   // country  → provinces
  districts: Record<string, string[]>   // province → districts
  schools:   Record<string, string[]>   // district → schools
  years:     number[]
  metrics:   string[]
  data:      DashboardRow[]
}
